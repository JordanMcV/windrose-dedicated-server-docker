# Windrose Dedicated Server — Docker + Wine

Run the Windows-only [Windrose](https://playwindrose.com/) dedicated server (Steam App `4129620`) on Linux via Docker + Wine + SteamCMD.

## Requirements

- Linux host with Docker 24+ and the Compose plugin.
- ~5 GB free disk, 8 GB RAM.
- Host networking available (no Docker Desktop).
- Outbound UDP to `*.windrose.support:3478` allowed.

## Quick start

```sh
cp .env.example .env
docker compose build
docker compose up -d
docker compose logs -f
```

First boot downloads ~3 GB via SteamCMD. Once the server is up:

```sh
docker exec windrose serverctl invite
```

Send the code to your players. No port forwarding needed.

## Configuration

Edit `.env`:

| Var | Default | Purpose |
|---|---|---|
| `PUID` / `PGID` | `1000` | UID/GID remap for the `steam` user. |
| `UPDATE_ON_START` | `true` | Run `steamcmd app_update` each start. `false` pins the installed build. |
| `WINDROSE_APP_ID` | `4129620` | Steam app ID. |
| `WINDROSE_SERVER_NAME` | _unset_ | Written to `ServerDescription.json` on boot when non-empty. |
| `WINDROSE_PASSWORD` | _unset_ | Sets password and `IsPasswordProtected=true`. |
| `WINEDEBUG` | `-all` | `""` for verbose Wine logs. |

For fields not exposed above, stop the container and edit `data/R5/ServerDescription.json` directly. Full field reference: `/data/server/DedicatedServer.md` inside the container.

## Operations

```sh
docker exec windrose serverctl status   # pgrep the shipping exe
docker exec windrose serverctl logs     # tail latest UE log
docker exec windrose serverctl invite   # print invite code
docker compose stop                     # 120 s grace — always use this, never kill
```

## License

MIT.
