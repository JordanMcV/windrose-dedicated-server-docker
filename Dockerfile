# syntax=docker/dockerfile:1.7
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    WINEARCH=win64 \
    WINEPREFIX=/home/steam/.wine \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree=;mshtml=" \
    SERVER_DIR=/data/server \
    WINDROSE_APP_ID=4129620

RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
        tini xvfb xauth \
        gosu procps \
        lib32gcc-s1 libstdc++6:i386 libcurl4:i386 \
        cabextract; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
        -o /etc/apt/keyrings/winehq-archive.key; \
    curl -fsSL https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
        -o /etc/apt/sources.list.d/winehq-bookworm.sources; \
    apt-get update; \
    apt-get install -y --install-recommends winehq-stable; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p /opt/steamcmd; \
    curl -fsSL https://media.steampowered.com/client/steamcmd_linux.tar.gz \
        | tar -xz -C /opt/steamcmd; \
    ln -sf /opt/steamcmd/steamcmd.sh /usr/local/bin/steamcmd

RUN set -eux; \
    groupadd -g 1000 steam; \
    useradd  -m -u 1000 -g 1000 -s /bin/bash steam; \
    mkdir -p /data/server /home/steam/.wine /config; \
    chown -R steam:steam /data /home/steam /opt/steamcmd /config

COPY --chmod=0755 scripts/entrypoint.sh  /usr/local/bin/entrypoint.sh
COPY --chmod=0755 scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY --chmod=0755 scripts/serverctl.sh   /usr/local/bin/serverctl

VOLUME ["/data/server", "/home/steam"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=600s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
