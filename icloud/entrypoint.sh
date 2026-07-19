#!/bin/sh
# Custom entrypoint for fnOS / non-privileged Docker hosts.
#
# The 'abc' user's uid/gid is already aligned to the host user at BUILD time
# (see Dockerfile: `usermod -u 1000 abc`), so no runtime `usermod`/`chown`/
# `su-exec` is needed here — those require root capabilities fnOS may not grant.
# We simply run the app as the already-correct 'abc' user.

# Sponsorship message.
echo "
====================================================
To support this project, please consider sponsoring.
https://github.com/sponsors/mandarons
===================================================="

# Display build version if available.
if [ -f /build_version ]; then
    cat /build_version
fi

# Persist python-keyring across container recreations.
export XDG_DATA_HOME=/config

echo "Starting iCloud Docker application as uid $(id -u abc) gid $(id -g abc)..."
exec /app/init.sh
