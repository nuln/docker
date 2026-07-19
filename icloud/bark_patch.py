"""Runtime monkey-patch injecting Bark into icloud-docker's notify module.

Importing this module (once) wraps the upstream notify.send() and
notify.send_sync_summary() so that, after the built-in channels fire,
a Bark notification is also sent when configured. No upstream files are
modified; everything is injected from outside, mirroring how
encrypted_keyring plugs into keyring via an env var.

Imported automatically at container start via sitecustomize.py.
"""

import functools
import logging

from src import config_parser, notify

import bark

LOGGER = logging.getLogger("bark_patch")


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
        total += getattr(summary.photo_stats, "photos_downloaded_bytes", 0) or 0
        # Fall back to bytes_downloaded if photos tracks it under that name.
        if total == 0:
            total += getattr(summary.photo_stats, "bytes_downloaded", 0) or 0
    return total


def _should_send_bark_sync_summary(config, summary) -> bool:
    """Only push Bark when real data was synced this cycle.

    Uses bytes_downloaded as the trigger: an empty cycle (0 B transferred,
    even if upstream reports hundreds of "downloaded" re-checked files) stays
    silent. 2FA alerts are handled separately and always fire.
    """
    if not config_parser.get_sync_summary_enabled(config=config):
        return False
    return _bytes_downloaded(summary) > 0


def _with_bark(original):
    """Wrap an upstream notify function so Bark also fires after it."""

    @functools.wraps(original)
    def wrapper(config, *args, **kwargs):
        result = original(config, *args, **kwargs)
        try:
            url, title, is_configured = bark.get_bark_config(config)
            if not is_configured:
                return result

            # Identify a sync_summary call (has a `summary` arg) vs a 2FA
            # `send` call (has `username`). Only suppress the summary path.
            summary = kwargs.get("summary")
            if summary is None and len(args) >= 2 and not kwargs.get("username"):
                # send_sync_summary passes summary as 2nd positional arg
                candidate = args[1]
                if hasattr(candidate, "drive_stats") or hasattr(candidate, "photo_stats"):
                    summary = candidate

            if summary is not None:
                # Only notify when real data was downloaded this cycle.
                if not _should_send_bark_sync_summary(config, summary):
                    return result

            message = _extract_message(args, kwargs)
            if message:
                bark.post_message_to_bark(url, title, message)
        except Exception as e:  # noqa: BLE001 - never break sync over notify
            LOGGER.error(f"Bark notify failed: {e!s}")
        return result

    return wrapper


def _extract_message(args, kwargs):
    """Pull a human-readable message out of the wrapped call's arguments.

    Calls may pass args positionally (sync.py uses notify.send(config, username, ...))
    or as keywords (notify.send(config=cfg, username=...)). Handle both.
    """
    # send_sync_summary(config, summary, dry_run=...)
    summary = kwargs.get("summary")
    if summary is None and len(args) >= 2:
        summary = args[1]

    if summary is not None:
        # Reuse upstream's formatter to produce the same text as other channels.
        try:
            message, _subject = notify._format_sync_summary_message(summary)
            if message:
                return message
        except Exception:  # noqa: BLE001 - fall through to 2FA path below
            pass

    # send(config, username, last_send, dry_run, region) -> 2FA alert
    username = kwargs.get("username")
    if username is None and len(args) >= 2:
        username = args[1]
    if username is not None:
        region = kwargs.get("region", "global")
        prefix = "" if region == "global" else f"--region={region} "
        return (
            f"iCloud 2FA required for {username}. Run:\n"
            f'icloud --session-directory=/config/session_data '
            f"{prefix}--username={username}"
        )
    return None


def patch():
    """Apply the Bark monkey-patch to the notify module."""
    notify.send = _with_bark(notify.send)
    notify.send_sync_summary = _with_bark(notify.send_sync_summary)
    LOGGER.info("Bark notification patch applied.")


patch()
