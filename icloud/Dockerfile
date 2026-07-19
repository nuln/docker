ARG ICD_VERSION=latest
FROM mandarons/icloud-drive:${ICD_VERSION}

USER root
RUN pip install --no-cache-dir cryptography

# Align the built-in 'abc' user with the fnOS host user at BUILD time.
# fnOS runs the container as a non-root user (the image's USER abc, uid 911),
# so a runtime `usermod` in the entrypoint cannot change the uid (no
# CAP_SETGID). By baking uid/gid 1000/1001 into the image here (build runs as
# root), the 'abc' user already matches the host bind-mount owner regardless
# of how the container is started. 1000/1001 = fnOS default user salute5611.
# Override with --build-arg if your host user differs.
ARG APP_UID=1000
ARG APP_GID=1001
RUN groupmod -o -g "${APP_GID}" abc \
    && usermod -o -u "${APP_UID}" abc \
    && mkdir -p /icloud /config/session_data /home/abc /config/python_keyring \
    && chown -R abc:abc /icloud /config /home/abc /app

COPY encrypted_keyring /app/encrypted_keyring
COPY bark /app/bark
COPY bark_patch.py /app/bark_patch.py

# Auto-apply the Bark monkey-patch at Python startup (no upstream edits needed).
COPY sitecustomize.py /app/sitecustomize.py

# Custom entrypoint: no privileged steps (no chown/su-exec) — the 'abc' uid is
# already aligned to the host at build time, so the app just runs as abc.
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh /app/init.sh

ENV PYTHONPATH=/app
ENV PYTHON_KEYRING_BACKEND=encrypted_keyring.EncryptedFileKeyring

USER abc
ENTRYPOINT ["/app/entrypoint.sh"]
