#!/usr/bin/env bash
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
UPDATE_ON_START="${UPDATE_ON_START:-true}"
WINDROSE_APP_ID="${WINDROSE_APP_ID:-4129620}"
SERVER_DIR="${SERVER_DIR:-/data/server}"
WINE_PREFIX="${WINEPREFIX:-/home/steam/.wine}"
SERVER_EXE_REL="R5/Binaries/Win64/WindroseServer-Win64-Shipping.exe"

log() { echo "[entrypoint] $*"; }

if [[ "$(id -u)" -ne 0 ]]; then
    log "must start as root for PUID/PGID remap (got uid=$(id -u))"
    exit 1
fi

current_uid="$(id -u steam)"
current_gid="$(id -g steam)"
if [[ "$current_gid" != "$PGID" ]]; then
    log "remapping group steam: $current_gid -> $PGID"
    groupmod -o -g "$PGID" steam
fi
if [[ "$current_uid" != "$PUID" ]]; then
    log "remapping user steam: $current_uid -> $PUID"
    usermod -o -u "$PUID" steam
fi

chown -R steam:steam /data /home/steam /opt/steamcmd

if [[ ! -f "$WINE_PREFIX/system.reg" ]]; then
    log "initializing Wine prefix at $WINE_PREFIX"
    gosu steam env \
        WINEPREFIX="$WINE_PREFIX" \
        WINEARCH=win64 \
        WINEDEBUG="${WINEDEBUG:--all}" \
        WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=;mshtml=}" \
        xvfb-run -a -- wineboot --init
    gosu steam env WINEPREFIX="$WINE_PREFIX" wineserver -w || true
fi

if [[ "$UPDATE_ON_START" == "true" ]] || [[ ! -x "$SERVER_DIR/$SERVER_EXE_REL" ]]; then
    log "running SteamCMD: app $WINDROSE_APP_ID -> $SERVER_DIR"
    # app_license_request blocks until Steam grants the anonymous license for
    # the app. Without it, app_update races the asynchronous PICS license sync
    # and fails with "Missing configuration" when it loses — most reliably
    # after wineboot, which shifts the timing.
    gosu steam steamcmd \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir "$SERVER_DIR" \
        +login anonymous \
        +app_license_request "$WINDROSE_APP_ID" \
        +app_update "$WINDROSE_APP_ID" validate \
        +quit
else
    log "UPDATE_ON_START=false and server binary present — skipping SteamCMD"
fi

if [[ ! -x "$SERVER_DIR/$SERVER_EXE_REL" ]]; then
    log "server binary missing at $SERVER_DIR/$SERVER_EXE_REL — SteamCMD install may have failed"
    exit 1
fi

if [[ -f /config/ServerDescription.json ]] && [[ ! -f "$SERVER_DIR/R5/ServerDescription.json" ]]; then
    log "seeding ServerDescription.json from /config (first run only)"
    install -o steam -g steam -m 0644 \
        /config/ServerDescription.json \
        "$SERVER_DIR/R5/ServerDescription.json"
fi

desc_path="$SERVER_DIR/R5/ServerDescription.json"
if [[ -f "$desc_path" ]] && { [[ -n "${WINDROSE_SERVER_NAME:-}" ]] || [[ -n "${WINDROSE_PASSWORD:-}" ]]; }; then
    log "applying ServerDescription overrides from env"
    tmp="$(mktemp)"
    jq \
        --arg name "${WINDROSE_SERVER_NAME:-}" \
        --arg pw   "${WINDROSE_PASSWORD:-}" \
        '
          (if $name != "" then .ServerDescription_Persistent.ServerName = $name else . end)
        | (if $pw   != "" then .ServerDescription_Persistent.Password = $pw
                               | .ServerDescription_Persistent.IsPasswordProtected = true
                           else . end)
        ' "$desc_path" > "$tmp"
    install -o steam -g steam -m 0644 "$tmp" "$desc_path"
    rm -f "$tmp"
fi

world_vars_set=false
for v in WINDROSE_MOB_HEALTH_MULTIPLIER WINDROSE_MOB_DAMAGE_MULTIPLIER \
         WINDROSE_SHIPS_HEALTH_MULTIPLIER WINDROSE_SHIPS_DAMAGE_MULTIPLIER \
         WINDROSE_BOARDING_DIFFICULTY_MULTIPLIER \
         WINDROSE_COOP_STATS_CORRECTION_MODIFIER \
         WINDROSE_COOP_SHIP_STATS_CORRECTION_MODIFIER \
         WINDROSE_COMBAT_DIFFICULTY \
         WINDROSE_SHARED_QUESTS WINDROSE_EASY_EXPLORE; do
    if [[ -n "${!v:-}" ]]; then world_vars_set=true; break; fi
done

if [[ "$world_vars_set" == "true" ]]; then
    log "applying WorldDescription overrides from env (forces WorldPresetType=Custom)"
    while IFS= read -r world_file; do
        tmp="$(mktemp)"
        jq \
            --arg mh  "${WINDROSE_MOB_HEALTH_MULTIPLIER:-}" \
            --arg md  "${WINDROSE_MOB_DAMAGE_MULTIPLIER:-}" \
            --arg sh  "${WINDROSE_SHIPS_HEALTH_MULTIPLIER:-}" \
            --arg sd  "${WINDROSE_SHIPS_DAMAGE_MULTIPLIER:-}" \
            --arg bd  "${WINDROSE_BOARDING_DIFFICULTY_MULTIPLIER:-}" \
            --arg cs  "${WINDROSE_COOP_STATS_CORRECTION_MODIFIER:-}" \
            --arg css "${WINDROSE_COOP_SHIP_STATS_CORRECTION_MODIFIER:-}" \
            --arg cd  "${WINDROSE_COMBAT_DIFFICULTY:-}" \
            --arg sq  "${WINDROSE_SHARED_QUESTS:-}" \
            --arg ee  "${WINDROSE_EASY_EXPLORE:-}" \
            '
            def fkey(n): "{\"TagName\": \"WDS.Parameter." + n + "\"}";
            def setf(n; v): if v != "" then .WorldDescription.WorldSettings.FloatParameters[fkey(n)] = (v | tonumber) else . end;
            def setb(n; v): if v != "" then .WorldDescription.WorldSettings.BoolParameters[fkey(n)]  = (v == "true") else . end;
              .WorldDescription.WorldPresetType = "Custom"
            | setf("MobHealthMultiplier";              $mh)
            | setf("MobDamageMultiplier";              $md)
            | setf("ShipsHealthMultiplier";            $sh)
            | setf("ShipsDamageMultiplier";            $sd)
            | setf("BoardingDifficultyMultiplier";     $bd)
            | setf("Coop.StatsCorrectionModifier";     $cs)
            | setf("Coop.ShipStatsCorrectionModifier"; $css)
            | setb("Coop.SharedQuests";                $sq)
            | setb("EasyExplore";                      $ee)
            | (if $cd != ""
                 then .WorldDescription.WorldSettings.TagParameters[fkey("CombatDifficulty")].TagName = "WDS.Parameter.CombatDifficulty." + $cd
                 else . end)
            ' "$world_file" > "$tmp"
        install -o steam -g steam -m 0644 "$tmp" "$world_file"
        rm -f "$tmp"
    done < <(find "$SERVER_DIR/R5/Saved/SaveProfiles/Default/RocksDB" -name 'WorldDescription.json' 2>/dev/null)
fi

cd "$SERVER_DIR"

log "launching WindroseServer under Wine + Xvfb"
exec gosu steam env \
    HOME=/home/steam \
    WINEPREFIX="$WINE_PREFIX" \
    WINEARCH=win64 \
    WINEDEBUG="${WINEDEBUG:--all}" \
    WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=;mshtml=}" \
    xvfb-run -a --server-args="-screen 0 1024x768x24" -- \
    wine "$SERVER_DIR/$SERVER_EXE_REL" -log
