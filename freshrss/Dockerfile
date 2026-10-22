# FreshRSS with multi-domain + sub-directory support.
#
# Upstream FreshRSS pins the instance to a single `base_url`, and assumes the public root can
# be derived from the current page. Both assumptions break behind a reverse proxy serving the
# instance from a sub-directory reachable through several domains:
#
#   * `Minz_Request::guessBaseUrl()` returned the directory of the *current page*, so
#     `Minz_Url::display()` appended `/i` a second time and produced `/rss/i/i`;
#   * `trim($conf->base_url, ' /\\"')` ate the leading slash, so a path-only `base_url` such as
#     `/rss` could not even be expressed;
#   * the session cookie path was derived from the backend entry-point directory, which does
#     not include the prefix stripped by a reverse proxy;
#   * `OIDCRedirectURI /i/oidc/` was hardcoded, so OIDC could not work under a sub-directory.
#
# A single patch fixes all of it; `patches/` holds the whole change so it can be reviewed and
# re-applied on a newer upstream release. See README.md.
#
# FreshRSS is licensed under AGPL-3.0; this image is a modified distribution and must keep
# offering the corresponding source (the patch that produced it is part of this repository).
# Base image. Debian is required for OIDC (`libapache2-mod-auth-openidc`); the Alpine image
# published by upstream does not ship it.
ARG FRESHRSS_BASE_IMAGE=debian:13-slim
FROM ${FRESHRSS_BASE_IMAGE}

ENV TZ=UTC
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
#
# The distribution packages are a *moving target*, and a cached apt layer freezes them forever.
# That is not a theoretical concern: CVE-2026-109618/9 are pre-auth RCEs in PHP itself, Debian
# shipped the fix as php8.4 8.4.27-1~deb13u1 on 2026-10-21, and an image rebuilt a day later with
# the same Dockerfile still contained 8.4.26 — BuildKit had reused the `apt-get install` layer,
# whose cache key is the command text, not the repository contents. The vulnerable build looked
# perfectly up to date (`git log` showed the new FreshRSS ref, the patch applied, every test green).
#
# So the apt layer is deliberately keyed to a caller-supplied *date*, not to the command. Set it to
# the day of the rebuild (`docker build --build-arg DEBIAN_APT_REFRESH=$(date -u +%Y-%m-%d)`); the
# build below refuses to run without a value, because silently reusing yesterday's packages is the
# failure mode this exists to prevent. It also matches the Debian snapshot convention of caching
# by date, and costs nothing when the layer is genuinely fresh.
ARG DEBIAN_APT_REFRESH
RUN if [ -z "${DEBIAN_APT_REFRESH}" ]; then \
		echo 'ERROR: pass --build-arg DEBIAN_APT_REFRESH=$(date -u +%Y-%m-%d) so this image' >&2; \
		echo '       gets the current Debian packages (PHP security updates included).' >&2; \
		exit 1; \
	fi && \
	apt-get update && \
	apt-get install --no-install-recommends -y \
	ca-certificates cron git patch nodejs \
	apache2 libapache2-mod-php \
	libapache2-mod-auth-openidc \
	php-curl php-gmp php-intl php-mbstring php-xml php-zip \
	php-sqlite3 php-mysql php-pgsql && \
	rm -rf /var/lib/apt/lists/* && \
	# Fail the build when the base distribution still ships a PHP older than the one that fixed
	# CVE-2026-109618/9. Only relevant while the base image is Debian 13 (`trixie`). Single-line on
	# purpose: a Dockerfile has no line continuation inside a quoted string.
	php -r 'if (version_compare(PHP_VERSION, "8.4.27", "<")) { fwrite(STDERR, "ERROR: this image ships PHP " . PHP_VERSION . " (< 8.4.27), vulnerable to CVE-2026-109618/9. Rebuild once Debian publishes php8.4 8.4.27+.\n"); exit(1); }' && \
	printf 'PHP %s (>= 8.4.27, CVE-2026-109618/9 fixed); Debian packages refreshed %s\n' \
		"$(php -r 'echo PHP_VERSION;')" "${DEBIAN_APT_REFRESH}"

RUN mkdir -p /var/www/FreshRSS/ /run/apache2/ /usr/src/freshrss-patches

# Upstream revision this image is built from. Bump it (and re-apply `patches/`) to update.
# 08f97bd4 is the `1.30.4` release tag.
ARG FRESHRSS_REF=08f97bd497ace733c151ea1c709d85cd5b65cc53
# Base branch, only used to give `git checkout` a name in error messages.
ARG FRESHRSS_BRANCH=1.30.4

WORKDIR /usr/src/freshrss

# Fetch the exact upstream tree, then apply the patch. `git apply --check` runs first so that a
# context mismatch fails the build with a readable message instead of a half-patched tree.
COPY patches/ /usr/src/freshrss-patches/
RUN git init -q . && \
	git remote add origin https://github.com/FreshRSS/FreshRSS.git && \
	git fetch -q --depth 1 origin "${FRESHRSS_REF}" && \
	git checkout -q FETCH_HEAD && \
	git log -1 --format='FreshRSS %H (%ad)' --date=short && \
	if ! git apply --check /usr/src/freshrss-patches/0001-multi-domain-and-subdirectory.patch; then \
		{ echo; echo '================================================================'; \
		  echo 'ERROR: patches/0001-multi-domain-and-subdirectory.patch no longer'; \
		  echo '       applies to FRESHRSS_REF='"${FRESHRSS_REF}"'.'; \
		  echo '       Rebase the patch (see README.md, "Updating FreshRSS").'; \
		  echo '================================================================'; } >&2 ; \
		exit 1 ; \
	fi && \
	git apply /usr/src/freshrss-patches/0001-multi-domain-and-subdirectory.patch && \
	echo 'Patch 0001 applied.' && \
	rm -rf .git && \
	cp -a /usr/src/freshrss/. /var/www/FreshRSS/ && \
	rm -rf /usr/src/freshrss

# Apache configuration: OIDC paths are driven by ${OIDC_REDIRECT_URI} / ${OIDC_DEFAULT_URL},
# exported by the entrypoint with the public path prefix applied.
COPY FreshRSS.Apache.conf /etc/apache2/sites-available/
COPY entrypoint.sh /usr/local/bin/freshrss-entrypoint
COPY healthcheck.sh /usr/local/bin/freshrss-healthcheck

ARG FRESHRSS_VERSION
ARG SOURCE_COMMIT

LABEL \
	org.opencontainers.image.description="FreshRSS, served from a sub-directory through one or several domains" \
	org.opencontainers.image.documentation="https://freshrss.github.io/FreshRSS/" \
	org.opencontainers.image.licenses="AGPL-3.0" \
	org.opencontainers.image.revision="${SOURCE_COMMIT}" \
	org.opencontainers.image.source="https://github.com/FreshRSS/FreshRSS" \
	org.opencontainers.image.title="FreshRSS" \
	org.opencontainers.image.url="https://freshrss.org/" \
	org.opencontainers.image.vendor="FreshRSS" \
	org.opencontainers.image.version="${FRESHRSS_VERSION}" \
	nuln.patch.freshrss-ref="${FRESHRSS_REF}" \
	nuln.patch.freshrss-branch="${FRESHRSS_BRANCH}" \
	# Which day the distribution packages were fetched, i.e. how old the PHP security patches are.
	nuln.base.apt-refresh="${DEBIAN_APT_REFRESH}"

RUN \
	chmod +x /usr/local/bin/freshrss-entrypoint /usr/local/bin/freshrss-healthcheck && \
	# Disable unwanted Apache modules and configurations
	a2dismod -q -f alias autoindex negotiation status && \
	a2dismod -q auth_openidc && \
	a2disconf -q '*' && \
	a2dissite -q '*' && \
	sed -r -i "/^\s*(CustomLog|ErrorLog|Listen) /s/^/#/" /etc/apache2/apache2.conf && \
	sed -r -i "/^\s*Listen /s/^/#/" /etc/apache2/ports.conf && \
	# Enable required Apache modules
	a2enmod -q deflate expires filter headers mime remoteip setenvif && \
	# Enable FreshRSS configuration for Apache
	a2ensite -q 'FreshRSS*' && \
	# Disable unwanted PHP modules
	phpdismod calendar exif ffi ftp gettext mysqli posix readline shmop sockets sysvmsg sysvsem sysvshm xsl && \
	# Disable built-in FreshRSS updates when using Docker, as the full image is supposed to be updated instead
	sed -r -i "\\#disable_update#s#^.*#\t'disable_update' => true,#" /var/www/FreshRSS/config.default.php && \
	# Configure cron job
	touch /var/www/FreshRSS/Docker/env.txt && \
	echo "7,37 * * * * . /var/www/FreshRSS/Docker/env.txt; \
		su www-data -s /bin/sh -c 'php /var/www/FreshRSS/app/actualize_script.php' \
		2>> /proc/1/fd/2 > /tmp/FreshRSS.log" > /etc/crontab.freshrss.default

ENV COPY_LOG_TO_SYSLOG=On
ENV COPY_SYSLOG_TO_STDERR=On
ENV CRON_MIN=''
ENV DATA_PATH=''
ENV ENABLE_ACCESS_LOG=1
ENV FRESHRSS_ENV=''
# Public sub-directory the instance is served from, e.g. `/rss`. Empty means domain root.
# Every domain must use the same prefix: https://a.example/rss and https://b.example/rss
#
# This is the ONLY setting needed for a sub-directory deployment: it drives the Apache
# `Alias`, the OIDC callback path, the session cookie path, and the `base_url` written by the
# installation wizard. `FRESHRSS_PATH_PREFIX=rss`, `rss/` and `/rss` are all accepted.
ENV FRESHRSS_PATH_PREFIX=''
# Pin the base URL through the environment instead of `./data/config.php`. Takes precedence
# over the configuration file. A full URL pins a single domain; a path such as `/rss` lets
# the host follow the request, so several domains share the instance.
# ENV FRESHRSS_BASE_URL=''
# Address advertised to WebSub hubs. Required (as a full URL) to enable WebSub when the base
# URL is a path, because the callback URL is built by the refresh cron job, outside of any
# HTTP request. Takes precedence over `websub_base_url` in `./data/config.php`.
# ENV FRESHRSS_WEBSUB_BASE_URL=''
ENV LISTEN=''
ENV OIDC_ENABLED=''
ENV TRUSTED_PROXY=''

HEALTHCHECK --interval=1m --timeout=10s --start-period=30s --retries=3 \
	CMD ["/usr/local/bin/freshrss-healthcheck"]

ENTRYPOINT ["/usr/local/bin/freshrss-entrypoint"]

EXPOSE 80
# hadolint ignore=DL3025
CMD ([ -z "$CRON_MIN" ] || cron) && \
	. /etc/apache2/envvars && \
	exec apache2 -D FOREGROUND $([ -n "$OIDC_ENABLED" ] && [ "$OIDC_ENABLED" -ne 0 ] && echo "-D OIDC_ENABLED")
