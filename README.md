# Windrose Dedicated Server — Docker + Wine

Run the Windows-only [Windrose](https://playwindrose.com/) dedicated server (Steam App `4129620`) on Linux inside Docker, using Wine and SteamCMD. The image installs nothing game-specific at build time — SteamCMD pulls the server into a mounted volume on first run.

## Requirements

- Linux host with Docker 24+ and the Compose plugin (`docker compose`).
- ~10 GB free disk for the server install.
- 8 GB RAM available to the container.
- Host networking (used for UPnP / NAT punch-through). Docker Desktop on macOS or Windows will not work — run this on a real Linux host.

## Quick start

```sh
cp .env.example .env
docker compose build
docker compose up -d
docker compose logs -f
```

First boot takes a while: SteamCMD downloads ~8 GB. Once the Windrose process is up, grab the invite code:

```sh
docker exec windrose serverctl invite
```

Players join with that code from the Windrose client — no port-forwarding needed.

## How it works

- **Base:** `debian:bookworm-slim` with i386 multiarch enabled.
- **Wine:** `winehq-stable` from the official WineHQ repo. Headless server; no Proton.
- **Display:** `xvfb-run -a` provides a throwaway X server — the Unreal shipping server occasionally wants one.
- **Init:** `tini` is PID 1 so `xvfb-run` behaves and `SIGTERM` propagates cleanly (Windrose needs ~90 s to flush saves).
- **Install:** SteamCMD runs as the non-root `steam` user against app `4129620` into `/data/server`, forcing the Windows platform.
- **Run:** `wine64 /data/server/R5/Binaries/Win64/WindroseServer-Win64-Shipping.exe -log`.

## Configuration

All config is via environment variables (see `.env.example`):

| Var | Default | Purpose |
|---|---|---|
| `PUID` / `PGID` | `1000` / `1000` | UID/GID the `steam` user is remapped to, so bind-mounted files stay owned by your host user. |
| `UPDATE_ON_START` | `true` | Run `steamcmd app_update` on every start. Set `false` to pin to the currently installed version. |
| `WINDROSE_APP_ID` | `4129620` | Steam app ID. Shouldn't change. |
| `WINEDEBUG` | `-all` | Wine log channels. Set to `""` for verbose diagnostics when debugging. |

Drop a `config/ServerDescription.json` before the first boot and it'll be seeded into the server install. Afterwards, edit `data/ServerDescription.json` directly while the container is stopped — the `DeploymentId` / `PersistentServerId` fields written by the server must be preserved.

## Pinning to a specific Windrose build

SteamCMD's anonymous update always pulls latest. To stay on a known-good build:

1. Let the container install once with `UPDATE_ON_START=true`.
2. Stop the container, set `UPDATE_ON_START=false` in `.env`.
3. Optionally snapshot `./data` (e.g. `tar -czf windrose-v1.2.3.tgz data/`).

The container will now keep running whatever version is on disk. True manifest-level pinning via `download_depot` is possible but fragile; revisit only if auto-update breaks your server.

## Operations

Inside the container there's a `serverctl` helper:

```sh
docker exec -it windrose serverctl status   # pgrep-based
docker exec -it windrose serverctl logs     # tail the newest UE log
docker exec -it windrose serverctl invite   # print invite code
docker exec -it windrose serverctl stop     # SIGTERM; let the healthcheck notice
```

Graceful shutdown: `docker compose stop` respects `stop_grace_period: 120 s` so the server can flush saves. Don't use `docker compose kill`.

## Known caveats

- **Not officially supported.** Any Windrose patch can break Wine compatibility. Keep snapshots of `./data` before pulling updates.
- **Outbound dependency:** the server must reach `*.windrose.support:3478` for P2P/TURN relay. Egress firewalls need to allow it.
- **Host networking only.** UPnP discovery needs it; bridged mode with dynamic ports won't work.
- **macOS hosts:** Docker Desktop's host-networking shim does not give the container real host interfaces — run this on Linux.

## Layout

```
Dockerfile
docker-compose.yml
.env.example
scripts/
  entrypoint.sh      # PUID remap, wine prefix init, steamcmd, exec server
  healthcheck.sh     # pgrep for the shipping exe
  serverctl.sh       # status / stop / logs / invite helpers
config/
  ServerDescription.example.json
```

## License

MIT.
