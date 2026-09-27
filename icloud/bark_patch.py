"""Runtime monkey-patch injecting Bark into icloud-docker's notify module.

Importing this module (once) wraps the upstream notify entry points so that,
after the built-in channels fire, a Bark notification is also sent when
configured. No upstream files are modified; everything is injected from
outside, mirroring how encrypted_keyring plugs into keyring via an env var.

Wrapped upstream functions (all three as of icloud-docker 2.0.0):

============================  =====================  ==========================
upstream function             Bark message            gated by
============================  =====================  ==========================
``notify.send``               2FA challenge          always
``notify.send_sync_summary``  sync summary           enabled + bytes > 0
``notify.send_trust_expiring`` trust expiry          always
============================  =====================  ==========================

The kind is bound when wrapping rather than sniffed from the call arguments:
each wrapper knows exactly which upstream function it fronts, so we never have
to guess whether ``args[1]`` is a username, a summary, or a day count. (The
pre-2.0.0 version inferred it by attribute-probing, which silently
mis-classified ``send_trust_expiring`` as a 2FA alert and would have told the
user to run the wrong command.)

Imported automatically at container start via sitecustomize.py.
"""

import functools
import logging

from src import config_parser, notify

import bark

LOGGER = logging.getLogger("bark_patch")

# Message kinds, bound at wrap time (see module docstring).
KIND_2FA = "2fa"
KIND_SUMMARY = "sync_summary"
KIND_TRUST_EXPIRING = "trust_expiring"


def _bytes_downloaded(summary) -> int:
    """Actual bytes transferred this sync cycle.

    Uses bytes_downloaded rather than the file count: upstream counts every
    file it re-checks/skips as "downloaded" (showing e.g. "642 files (0 B)"),
    so a non-zero file count with 0 bytes means nothing new was actually
    fetched. Only real transferred bytes indicate a successful sync with new
    data -- that's what we want to alert on.
    """
    total = 0
    if getattr(summary, "drive_stats", None) is not None:
        total += getattr(summary.drive_stats, "bytes_downloaded", 0) or 0
    if getattr(summary, "photo_stats", None) is not None:
        total += getattr(summary.photo_stats, "bytes_downloaded", 0) or 0
    return total


def _should_send_bark_sync_summary(config, summary) -> bool:
    """Only push Bark when real data was synced this cycle.

    Uses bytes_downloaded as the trigger: an empty cycle (0 B transferred,
    even if upstream reports hundreds of "downloaded" re-checked files) stays
    silent. 2FA and trust-expiry alerts are handled separately and always fire.
    """
    if not config_parser.get_sync_summary_enabled(config=config):
        return False
    return _bytes_downloaded(summary) > 0


def _get_arg(args, kwargs, name, index):
    """Read a parameter that upstream may pass positionally or by keyword.

    All notify entry points are called with keyword arguments upstream, but
    positional calls are supported so the patch keeps working if that changes.
    """
    value = kwargs.get(name)
    if value is None and len(args) > index:
        return args[index]
    return value


def _with_bark(original, kind):
    """Wrap an upstream notify function so Bark also fires after it."""

    @functools.wraps(original)
    def wrapper(config, *args, **kwargs):
        result = original(config, *args, **kwargs)
        try:
            url, title, is_configured = bark.get_bark_config(config)
            if not is_configured:
                return result

            if kind == KIND_SUMMARY:
                # Only notify when real data was downloaded this cycle.
                summary = _get_arg(args, kwargs, "summary", 1)
                if not _should_send_bark_sync_summary(config, summary):
                    return result

            message = _extract_message(args, kwargs, kind)
            if message:
                bark.post_message_to_bark(url, title, message)
        except Exception as e:  # noqa: BLE001 - never break sync over notify
            LOGGER.error(f"Bark notify failed: {e!s}")
        return result

    return wrapper


def _extract_message(args, kwargs, kind):
    """Build the Bark body for the wrapped call.

    Each kind gets text appropriate to it: sync summaries reuse upstream's own
    formatter so Bark reads exactly like the other channels; the 2FA text is
    ours because upstream's tells the user to run
    ``docker exec ... su-exec abc icloud ...``, which fails on unprivileged
    hosts like fnOS (no CAP_SETGID) -- we print the plain in-container command
    that actually works there, plus the Web UI link when one is configured.
    """
    if kind == KIND_SUMMARY:
        summary = _get_arg(args, kwargs, "summary", 1)
        if summary is not None:
            try:
                message, _subject = notify._format_sync_summary_message(summary)
                if message:
                    return message
            except Exception:  # noqa: BLE001 - fall through, never break sync
                LOGGER.debug("Upstream sync-summary formatter failed", exc_info=True)
        return None

    username = _get_arg(args, kwargs, "username", 1)

    if kind == KIND_TRUST_EXPIRING:
        days_remaining = _get_arg(args, kwargs, "days_remaining", 2)
        if days_remaining is None or username is None:
            return None
        dashboard_url = kwargs.get("dashboard_url")
        try:
            message, _subject = notify._create_trust_expiring_message(
                username,
                days_remaining,
                dashboard_url=dashboard_url,
            )
            if message:
                return message
        except Exception:  # noqa: BLE001 - fall back to our own wording
            LOGGER.debug("Upstream trust-expiry formatter failed", exc_info=True)
        horizon = "today" if days_remaining <= 0 else f"in {days_remaining} day(s)"
        message = (
            f"iCloud login for {username} expires {horizon}. "
            "Re-authenticate before the next sync fails."
        )
        if dashboard_url:
            message = f"{message} Refresh at {dashboard_url}"
        return message

    # 2FA challenge: notify.send(config, username, last_send, dry_run, region)
    if username is None:
        return None
    region = kwargs.get("region", "global")
    prefix = "" if region == "global" else f"--region={region} "
    message = (
        f"iCloud 2FA required for {username}. Run:\n"
        f'icloud --session-directory=/config/session_data '
        f"{prefix}--username={username}"
    )
    dashboard_url = kwargs.get("dashboard_url")
    if dashboard_url:
        # Web UI is enabled: signing in there is easier than docker exec.
        message = f"{message}\nOr sign in at {dashboard_url}/auth"
    return message


def patch():
    """Apply the Bark monkey-patch to the notify module."""
    notify.send = _with_bark(notify.send, KIND_2FA)
    notify.send_sync_summary = _with_bark(notify.send_sync_summary, KIND_SUMMARY)
    # Added upstream in 2.0.0: warns N days before Apple's ~90-day trust
    # cookie expires, so trust can be refreshed before a sync failure.
    if hasattr(notify, "send_trust_expiring"):
        notify.send_trust_expiring = _with_bark(
            notify.send_trust_expiring,
            KIND_TRUST_EXPIRING,
        )
    else:  # pragma: no cover - older upstream without trust-expiry alerts
        LOGGER.info("Upstream has no send_trust_expiring; skipping that channel.")
    LOGGER.info("Bark notification patch applied.")


patch()
