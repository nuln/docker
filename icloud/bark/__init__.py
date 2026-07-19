"""Bark notification support for icloud-docker.

Sends iCloud sync summaries (and 2FA alerts) to a Bark server
(https://github.com/Finb/Bark). Injected at runtime via bark_patch.py.

Configuration uses a single full ``url`` — your complete Bark push address,
which already embeds the device key and any personalization params
(icon, sound, group, isArchive, level, …). We only append the
``/<title>/<body>`` path segment and leave your query string untouched,
so every Bark feature keeps working:

    app:
      bark:
        url: "https://nulnul.cn/bark/9cEfhN6MWdRcVyCUnt9DzD?isArchive=1&sound=minuet&icon=..."
        title: "iCloud Sync"   # optional
"""

import logging
import urllib.parse

import requests

LOGGER = logging.getLogger(__name__)


def get_bark_config(config):
    """Extract Bark configuration from config dict.

    Expected config shape:
        app:
          notifications:
            bark:
              url: "https://nulnul.cn/bark/<key>?isArchive=1&..."  # required
              title: "iCloud Sync"                                 # optional

    Returns:
        Tuple of (url, title, is_configured)
    """
    try:
        bark = config["app"]["notifications"]["bark"]
    except (KeyError, TypeError):
        return None, None, False

    if not isinstance(bark, dict):
        return None, None, False

    url = bark.get("url")
    title = bark.get("title") or "iCloud Sync"
    is_configured = bool(url)
    return url, title, is_configured


def post_message_to_bark(url: str, title: str, message: str) -> bool:
    """Post a message to a Bark server using the prebuilt ``url``.

    ``url`` already contains the device key and any query params the user
    set (icon/sound/group/…). Bark expects ``/<key>/<title>/<body>`` as the
    path and all customization params as the query string. So we split the
    user's URL: its path becomes the key prefix, its query params are moved
    to the END after we append ``/<title>/<body>``. This keeps the user's
    params (sound/group/icon/…) working while the body is correctly placed.

    Args:
        url: Full Bark push URL (key + params included)
        title: Notification title
        message: Notification body

    Returns:
        True if delivered successfully, False otherwise.
    """
    parsed = urllib.parse.urlparse(url)
    # Path holds the key (e.g. /bark/<key>); strip trailing slash.
    key_path = parsed.path.rstrip("/")
    # safe="" encodes slashes too, so the body can never inject extra path
    # segments (e.g. a "/config/..." leak).
    full_url = (
        f"{parsed.scheme}://{parsed.netloc}{key_path}"
        f"/{urllib.parse.quote(title, safe='')}"
        f"/{urllib.parse.quote(message, safe='')}"
    )
    if parsed.query:
        full_url = f"{full_url}?{parsed.query}"
    try:
        response = requests.get(full_url, timeout=10)
        # Bark returns JSON {"code": 200, ...} on success.
        try:
            payload = response.json()
            if payload.get("code") == 200:
                return True
        except ValueError:
            pass
        if response.status_code == 200:
            return True
        LOGGER.error(f"Failed to send Bark notification. Response: {response.text}")
        return False
    except Exception as e:  # noqa: BLE001 - surface any network error to caller
        LOGGER.error(f"Failed to send Bark notification: {e!s}")
        return False
