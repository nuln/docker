"""Auto-import Bark patch when the icloud app starts.

Because PYTHONPATH=/app, this module is picked up by Python as the
sitecustomize hook and runs before main.py, injecting Bark support
into src.notify.
"""

try:
    import bark_patch  # noqa: F401 - applies the monkey-patch on import
except Exception as e:  # noqa: BLE001 - never break startup over notifications
    import logging

    logging.getLogger(__name__).warning(f"Bark patch failed to load: {e!s}")
