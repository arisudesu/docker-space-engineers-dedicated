FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

ARG WINE_BRANCH=stable
ARG WINE_VERSION=9.0.0.0~bookworm-1

ENV WINEARCH=win64
ENV WINEDEBUG=-all
ENV WINEPREFIX=/appuser/.wineprefix

RUN set -x \
    && apt update \
    && apt install -y --no-install-recommends \
        ca-certificates \
        wget \
    && dpkg --add-architecture i386 \
    && mkdir -pm0755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
    && sed -i 's/Components:.*/& non-free/' /etc/apt/sources.list.d/debian.sources \
    && echo steam steam/question select "I AGREE" | debconf-set-selections \
    && echo steam steam/license note '' | debconf-set-selections \
    && apt update \
    && apt install -y --no-install-recommends \
        cabextract \
        psmisc \
        steamcmd \
        winehq-${WINE_BRANCH}=${WINE_VERSION} \
        wine-${WINE_BRANCH}-i386=${WINE_VERSION} \
        wine-${WINE_BRANCH}-amd64=${WINE_VERSION} \
        wine-${WINE_BRANCH}=${WINE_VERSION} \
        xvfb \
    && wget -O /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    && chmod 0755 /usr/local/bin/winetricks \
    && groupadd -g 18000 steamuser \
    && useradd -u 18000 -s /bin/bash -m -d /appuser -g steamuser steamuser \
    && su steamuser -c 'set -x \
        && Xvfb :5 -screen 0 1024x768x16 & xsrvpid=$! \
        && env WINEDLLOVERRIDES="mscoree=d" wineboot --init /nogui \
        && wine winecfg /v win10 \
        && winetricks corefonts \
        && winetricks sound=disabled \
        && env DISPLAY=:5.0 winetricks -q vcrun2019 \
        && env DISPLAY=:5.0 winetricks -q --force dotnet48 \
        && kill $xsrvpid \
        && wait' \
    && rm -rf /appuser/.cache \
    && apt autoremove -y --purge \
        cabextract \
        xvfb \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -pm0755 /appdata \
    && chown steamuser: /appdata

COPY docker-entrypoint.sh /

USER 18000:18000

ENTRYPOINT ["/docker-entrypoint.sh"]
