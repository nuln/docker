# iCloud

An encrypted-credential iCloud backup image, based on [mandarons/icloud-docker](https://github.com/mandarons/icloud-docker). The Apple ID password is AES-encrypted before being written to disk, so **even with the data volume alone the password cannot be recovered** (the encryption passphrase `KEYRING_PASSPHRASE` exists only at runtime and is never written to disk).

## Build

The image is built automatically by CI (`.github/workflows/icloud.yml`) for multiple architectures (amd64/arm64) and pushed to:

```
ghcr.io/nuln/icloud:latest
ghcr.io/nuln/icloud:<upstream version>
```

The version is taken from the latest upstream `mandarons/icloud-docker` release (the Dockerfile pins it via `ARG ICD_VERSION`). To build locally:

```bash
docker build -t ghcr.io/nuln/icloud:latest icloud
```

## Usage

```bash
cd icloud
cp .env.sample .env
# Fill KEYRING_PASSPHRASE in .env (generate a strong passphrase with `openssl rand -base64 24`)
docker compose up -d
```

First login (required, includes 2FA), run in the container terminal:

```sh
su-exec abc icloud --username=yourAppleID --session-directory=/config/session_data
```

Enter password + 2FA as prompted; after success, restart the container to sync automatically per `sync_interval`.

## Config

- `config/config.yaml`: set `app.credentials.username` to your Apple ID; for China region set `region: china`
- Backup data: `./data/drive/` (iCloud Drive), `./data/photos/` (Photos)
- Credential ciphertext: `./config/python_keyring/encrypted_keyring.json`

### Bark notifications (iOS push)

The image has Bark push built in (injected via a runtime monkey-patch, no upstream code changes). Fill the **full push URL** in the `app.bark` section of `config/config.yaml`; it triggers together with `sync_summary` (sync success/failure summary, plus 2FA-expiry alerts):

```yaml
app:
  bark:
    url: "https://nulnul.cn/bark/yourBarkDeviceKey?isArchive=1&sound=minuet&group=icloud"
    title: "iCloud Sync"            # optional
```

- `url` is the address you get from "copy key" in the Bark App; you may append any custom params (`icon`, `sound`, `group`, `level`, `isArchive`, etc.) — the image only appends `/<title>/<body>` after it and **does not alter any of your existing params**.
- Official server example: `https://api.day.app/<key>?isArchive=1`; for self-hosted, change to your domain.
- Bark connects directly over HTTPS; a domestic NAS **needs no proxy** (unlike Telegram).
- **Notifies only when data is actually synced**: Bark uses actual downloaded bytes `bytes_downloaded > 0` as the threshold. Upstream counts every re-verified/skipped file as `files_downloaded` (shows as "Downloaded: 642 files (0 B)"), but such empty cycles have 0 bytes and Bark **does not push**, avoiding hourly empty-run spam. Only a real new-content pull (bytes > 0) notifies. The 2FA (two-factor expiry) alert is exempt and pushes every time.

## fnOS / unprivileged Docker deployment notes

At **build time** the image fixes the built-in `abc` user's uid/gid to `1000:1001` (i.e. the fnOS default user `salute5611` = uid 1000 / gid 1001(Users)), so the in-container process naturally aligns with the host mount owner and **needs no root privilege, no `usermod`/`chown`/`su-exec` at runtime** (the upstream default entrypoint relies on these privileged ops and errors out under fnOS's restricted environment — which is why this image ships its own `entrypoint.sh`).

Deployment points:

1. **Mount directory ownership**: on fnOS, the `config` and `data` directories should be owned by `1000:1001` (your own user). If you previously created them as root or another user and ownership is wrong, in the fnOS terminal run:
   ```sh
   chown -R 1000:1001 /your/icloud/dir/config /your/icloud/dir/data
   ```
2. **PUID / PGID env vars**: you may set `PUID=1000`, `PGID=1001` (recorded only; the actual uid is baked into the image). If your fnOS user uid/gid is not 1000/1001, rebuild the image with `--build-arg APP_UID=xxx APP_GID=xxx`.
3. **No `privileged` needed**: a normal container runs fine.

> If you see `Permission denied` after start, first `ls -ld <mount dir>` to confirm ownership is `1000:1001`; if not, fix it with the `chown` above.

## First login (required, includes 2FA)

After the container starts it is in a "waiting for login" state (log: `Password is not stored in keyring. Retrying login...`). Run in the container terminal:

```sh
icloud --username=yourAppleID --session-directory=/config/session_data
```

> **Note**: do not use `su-exec abc icloud ...`. Unprivileged environments like fnOS lack `CAP_SETGID`, so `su-exec` errors with `setgroups: Operation not permitted`. The current in-container user **is already `abc` (uid 1000)**, so just run `icloud` directly — no user switch needed.
>
> If you get `icloud: command not found`, use the absolute-path form:
> ```sh
> cd /app && PYTHONPATH=/app HOME=/home/abc python /app/src/main.py --username=yourAppleID --session-directory=/config/session_data
> ```

Enter password + 2FA as prompted; after success, restart the container to sync automatically per `sync_interval`.

## Notes

- `KEYRING_PASSPHRASE` must be the **same** on every start; if forgotten, you can only delete `config/python_keyring/` and log in again.
- `remove_obsolete` is always kept `false` (prevents server-side deletion from wiping local backups).
- Low-power defaults: `mem_limit 1g / cpus 2`; no exposed ports (sync is outbound).
