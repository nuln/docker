# docker repository

A unified Docker image build repository containing multiple **self-contained sub-projects**. Each sub-project has its own directory with its own `Dockerfile` / `docker-compose.yml` / docs, and CI workflows live under `.github/workflows/` at the repo root.

## Sub-projects

| Directory | Image | Description |
|-----------|-------|-------------|
| `caddy/` | `ghcr.io/nuln/caddy` | Custom Caddy (with caddy-l4 plugin), reverse proxy / static site / UDP forwarding |
| `icloud/` | `ghcr.io/nuln/icloud` | Encrypted-credential iCloud backup (based on mandarons/icloud-docker) |
| `pi-dev/` | `ghcr.io/nuln/pi-dev` | Pi coding agent container: Node 24 + s6-overlay, 14 curated plugins baked into the image layer (wire-plugins writes absolute-path settings.json on first boot) + Web UI autostart + on-demand toolchains |

Each sub-project directory has its own documentation describing config, usage, and development notes.

## CI rules (important)

- **Workflow location**: only under the repo root `.github/workflows/`; a `.github` directory inside a sub-directory is not scanned/executed by GitHub Actions.
- **Naming rule**: `<sub-project>.yml` (e.g. `caddy.yml`, `pi-dev.yml`).
- **Trigger isolation**: each workflow filters by `paths` (e.g. `pi-dev/**`) so it only builds when the corresponding sub-project changes, with no interference between them.
- **Multi-arch**: uniformly `linux/amd64` + `linux/arm64` (`QEMU` + `buildx`).
- **Push target**: `ghcr.io/nuln/<sub-project>`, tagged `latest` + version.
- **Auth**: `GITHUB_TOKEN` (no extra secret needed).

## Steps to add a new sub-project

1. Create a sub-directory at the repo root (e.g. `nginx/`) and add the `Dockerfile` etc.
2. Create `<sub-project>.yml` under `.github/workflows/`, copying an existing yml and changing `context`, `paths`, version source, and push image name.
3. Write the sub-project's documentation and `.gitignore` (ignore runtime data).
4. `git push` to `main`, CI builds automatically and pushes `ghcr.io/nuln/<sub-project>`.
