#!/bin/bash
# FreshRSS entrypoint: sub-directory + multi-domain aware.
#
# Responsibilities:
#  1. normalise FRESHRSS_PATH_PREFIX (e.g. "", "/", "/rss", "rss/" -> "/rss")
#  2. export the OIDC paths with that prefix applied, so that mod_auth_openidc serves its
#     callback under the *public* URL and can be reached through every configured domain
#  3. generate the Apache `Alias` serving the public prefix from FreshRSS `p/` directory
#  4. hand over to the upstream entrypoint (cron, Apache, …)
#
# All steps are idempotent: the container can be restarted any number of times.
set -euo pipefail

FRESH_RSS_ROOT=/var/www/FreshRSS
PREFIX_CONF=/etc/apache2/conf-available/freshrss-path-prefix.conf

# --------------------------------------------------------------------------------------------
# 1. Normalise the public path prefix.
# --------------------------------------------------------------------------------------------
# FRESHRSS_PATH_PREFIX: sub-directory the instance is served from. Empty or "/" means the
# instance is at the domain root. Example: "/rss" -> https://example.net/rss/
FRESHRSS_PATH_PREFIX="${FRESHRSS_PATH_PREFIX:-}"
FRESHRSS_PATH_PREFIX="/$(printf '%s' "${FRESHRSS_PATH_PREFIX#/}" | sed 's#/*$##')"
if [ "${FRESHRSS_PATH_PREFIX}" = "/" ]; then
	FRESHRSS_PATH_PREFIX=''
fi
export FRESHRSS_PATH_PREFIX
# Always give Apache an explicit, non-empty value: an undefined ${VAR} expands to nothing and
# would turn `OIDCRedirectURI ${OIDC_REDIRECT_URI}` into a directive without argument.
export OIDC_REDIRECT_URI="${FRESHRSS_PATH_PREFIX}/i/oidc/"
export OIDC_DEFAULT_URL="${FRESHRSS_PATH_PREFIX}/i/"
export OIDC_X_FORWARDED_HEADERS="${OIDC_X_FORWARDED_HEADERS:-X-Forwarded-Host X-Forwarded-Proto X-Forwarded-Port}"

echo "FreshRSS: public path prefix = '${FRESHRSS_PATH_PREFIX:-/ (domain root)}'"

# --------------------------------------------------------------------------------------------
# 1b. Make the data directory usable by the Apache workers.
# --------------------------------------------------------------------------------------------
# FreshRSS keeps per-feed WebSub state in data/PubSubHubbub/ (one directory per topic, plus a key
# file per subscription). Those are created by *root* — the CLI and the refresh cron run as root —
# with mode 0770, which the 022 umask turns into 0750 owned by root:root. The Apache workers run as
# www-data, which is neither the owner nor in group root, so they cannot traverse into those
# directories and every WebSub callback answers 410 "Feed info not found!".
#
# Two things prevent it, and both are needed:
#   * a group-friendly umask, so anything this entrypoint's children create is group-accessible;
#   * setgid on the data directories, so a subdirectory created *later* by root inherits the
#     www-data group instead of root's.
# Without setgid, fixing the permissions once at start-up is not enough: the first actualisation
# after that creates fresh directories with the wrong group again.
# (Invisible when testing on macOS or Windows: Docker Desktop's file sharing bypasses these checks.)
if [ "$(id -u)" = "0" ] && [ -d "${FRESH_RSS_ROOT}/data" ]; then
	umask 002
	www_group=''
	for candidate in www-data apache http; do
		if getent group "$candidate" >/dev/null 2>&1; then
			www_group="$candidate"
			break
		fi
	done
	if [ -n "$www_group" ]; then
		chown -R ":${www_group}" "${FRESH_RSS_ROOT}/data" 2>/dev/null || true
		chmod -R g+rX "${FRESH_RSS_ROOT}/data" 2>/dev/null || true
		chmod -R g+w "${FRESH_RSS_ROOT}/data" 2>/dev/null || true
		find "${FRESH_RSS_ROOT}/data" -type d -exec chmod g+s {} + 2>/dev/null || true
		echo "FreshRSS: data/ is group-writable by ${www_group} (setgid), so WebSub state stays reachable"
	else
		echo "FreshRSS: WARNING — no Apache group {www-data, apache, http} found; WebSub callbacks may answer 410" >&2
	fi
fi

# --------------------------------------------------------------------------------------------
# 1c. Make the refresh cron actually get installed.
# --------------------------------------------------------------------------------------------
# Upstream writes /etc/crontab.freshrss.default with the schedule already in place
# (`7,37 * * * * . …`), and then replaces only the FIRST whitespace-delimited field with the whole
# of $CRON_MIN (`s#^[^ ]+ #$CRON_MIN #`). The result carries ten fields instead of five, cron
# rejects it with `bad command`, and no crontab is installed at all — so the documented feed refresh
# never runs. The same holds when CRON_MIN is unset, because the whole block is then skipped.
#
# Two adjustments fix it without reimplementing the cron wiring:
#   * collapse the template down to a single placeholder field, so upstream's substitution yields a
#     valid five-field schedule;
#   * default CRON_MIN to the schedule the image documents, so the block is never skipped.
if [ -f /etc/crontab.freshrss.default ]; then
	sed -r -i 's#^[^ ]+([ \t]+\*[ \t]+\*[ \t]+\*[ \t]+\*)?[ \t]*#CRON_PLACEHOLDER #' \
		/etc/crontab.freshrss.default
fi
export CRON_MIN="${CRON_MIN:-7,37 * * * *}"

# CRON_MIN replaces the WHOLE schedule, so a value that reads like a minute field — `*/30`, which is
# exactly what the name suggests — is substituted in place of the minute field and leaves the rest
# of the template to be parsed as the hour field. cron then either fails outright (`bad hour`) or,
# on a more tolerant build, installs a line whose command is `.`, i.e. it sources env.txt every half
# hour instead of refreshing feeds. Fewer than five fields can only be an incomplete schedule, so
# complete it. `@`-prefixed shorthands (@daily …) are already whole schedules and are left alone.
case "$CRON_MIN" in
	@*) ;;
	*)
		if [ "$(printf '%s' "$CRON_MIN" | awk '{print NF}')" -lt 5 ]; then
			export CRON_MIN="$CRON_MIN * * * *"
			echo "FreshRSS: CRON_MIN has fewer than five fields, using '$CRON_MIN' as the complete schedule"
		fi
		;;
esac

# --------------------------------------------------------------------------------------------
# 2. Serve the public prefix from the FreshRSS `p/` directory.
# --------------------------------------------------------------------------------------------
# The reverse proxy forwards the path unchanged and Apache aliases the prefix, so that:
#  - SCRIPT_NAME carries the prefix, which is how FreshRSS derives its public root;
#  - mod_auth_openidc can match OIDCRedirectURI against the path it actually serves;
#  - PHP session cookies are scoped to a path the browser can match.
: > "${PREFIX_CONF}"
if [ -n "${FRESHRSS_PATH_PREFIX}" ]; then
	# `mod_alias` is disabled by the upstream image as a hardening measure. It is required
	# here: `Alias` is the only mapping that keeps the public prefix in `SCRIPT_NAME`, which
	# FreshRSS uses to derive its public root and mod_auth_openidc uses to match
	# OIDCRedirectURI. The target below is the very same directory as `DocumentRoot`, so no
	# additional path becomes reachable, and the prefix is normalised above.
	a2enmod -q alias
	{
		echo "# Generated by FreshRSS entrypoint — do not edit, regenerated on every start."
		echo "Alias \"${FRESHRSS_PATH_PREFIX}/\" \"${FRESH_RSS_ROOT}/p/\""
		echo "Alias \"${FRESHRSS_PATH_PREFIX}\" \"${FRESH_RSS_ROOT}/p/index.php\""
	} > "${PREFIX_CONF}"
	echo "FreshRSS: serving ${FRESHRSS_PATH_PREFIX}/ -> ${FRESH_RSS_ROOT}/p/ (Apache Alias)"
else
	echo "FreshRSS: served at the domain root, no Alias needed"
fi

# Fail fast on a broken configuration instead of serving 500s.
# envvars first: apache2.conf relies on ${APACHE_RUN_DIR} and friends. It reads optional
# variables, so relax `nounset` around it.
# shellcheck disable=SC1091
if [ -f /etc/apache2/envvars ]; then
	set +u
	. /etc/apache2/envvars
	set -u
fi
if ! apache2 -t >/dev/null 2>&1; then
	echo "FreshRSS: FATAL — invalid Apache configuration:" >&2
	apache2 -t >&2 || true
	exit 1
fi

# --------------------------------------------------------------------------------------------
# 2b. Refuse to stay silent when the public prefix and the stored base_url disagree.
# --------------------------------------------------------------------------------------------
# These two have to describe the same address, and nothing else checks it:
#   * the Apache Alias and the session cookie path follow FRESHRSS_PATH_PREFIX;
#   * every generated link and every redirect target follows `base_url` in data/config.php.
# When they disagree the instance starts, serves 200s, and the browser is quietly moved out of
# the sub-directory on the first login — the cookie is scoped to /rss/ but the redirect lands on
# /i/, so the session never comes back and the login page repeats forever.
# Say what the Content-Security-Policy will actually contain, so a deployment that expects a
# relaxed policy can confirm from `docker logs` that the variable reached the container at all —
# an entry in `.env` alone does nothing unless the compose file passes it through.
if [ -n "${FRESHRSS_CSP_SCRIPT_SRC:-}" ]; then
	echo "FreshRSS: CSP script-src = ${FRESHRSS_CSP_SCRIPT_SRC} (from the environment)"
fi

if [ -f "${FRESH_RSS_ROOT}/data/config.php" ]; then
	# Read the stored value rather than sourcing the file: config.php is PHP, not shell.
	stored_base=$(sed -n "s/^[[:space:]]*'base_url'[[:space:]]*=>[[:space:]]*'\(.*\)',[[:space:]]*$/\1/p" \
		"${FRESH_RSS_ROOT}/data/config.php" | head -1)
	stored_base="${stored_base%/}"
	# An unset base_url means "follow the request host", which is the documented way to serve
	# several domains from one instance; an empty one is therefore not a value to compare.
	if [ -n "${FRESHRSS_PATH_PREFIX}" ] && [ -z "${stored_base}" ]; then
		echo "FreshRSS: WARNING — FRESHRSS_PATH_PREFIX is '${FRESHRSS_PATH_PREFIX}' but" >&2
		echo "          data/config.php has an empty base_url. Links will be built without the" >&2
		echo "          prefix while the session cookie is scoped to '${FRESHRSS_PATH_PREFIX}/'," >&2
		echo "          so a login will bounce back to the login form." >&2
		echo "          Fix with: docker exec freshrss php cli/reconfigure.php --base-url '${FRESHRSS_PATH_PREFIX}'" >&2
		echo "          — or serve the instance at the domain root by unsetting FRESHRSS_PATH_PREFIX." >&2
	elif [ -z "${FRESHRSS_PATH_PREFIX}" ] && [ -n "${stored_base}" ]; then
		echo "FreshRSS: WARNING — data/config.php pins base_url to '${stored_base}' but" >&2
		echo "          FRESHRSS_PATH_PREFIX is unset, so the container serves no such sub-directory." >&2
		echo "          Set FRESHRSS_PATH_PREFIX='${stored_base}' on the container." >&2
	elif [ -n "${FRESHRSS_PATH_PREFIX}" ] && [ -n "${stored_base}" ] \
		&& [ "${stored_base}" != "${FRESHRSS_PATH_PREFIX}" ]; then
		echo "FreshRSS: WARNING — FRESHRSS_PATH_PREFIX ('${FRESHRSS_PATH_PREFIX}') and the stored" >&2
		echo "          base_url ('${stored_base}') disagree; links and cookies will not match." >&2
	fi
fi

# --------------------------------------------------------------------------------------------
# 3. Hand over to the upstream entrypoint.
# --------------------------------------------------------------------------------------------
cd "${FRESH_RSS_ROOT}"
exec ./Docker/entrypoint.sh "$@"
