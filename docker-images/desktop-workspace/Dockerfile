# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie

# set version label
ARG BUILD_DATE
ARG VERSION
ARG CHROME_VERSION
ARG OBSIDIAN_VERSION
LABEL build_version="Desktop Workspace version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="Yakrel"

# title
ENV TITLE="Desktop Workspace"

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/chrome-logo.png && \
  echo "**** setup repo ****" && \
  curl -fsSL \
    https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor | tee /usr/share/keyrings/google-chrome.gpg >/dev/null && \
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" >> \
    /etc/apt/sources.list.d/google-chrome.list && \
  echo "**** install packages ****" && \
  if [ -z "${CHROME_VERSION+x}" ]; then \
    CHROME_VERSION=$(curl -sX GET http://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages | grep -A 7 -m 1 'Package: google-chrome-stable' | awk -F ': ' '/Version/{print $2;exit}'); \
  fi && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    google-chrome-stable=${CHROME_VERSION} && \
  echo "**** install Obsidian dependencies ****" && \
  apt-get install -y --no-install-recommends \
    chromium \
    chromium-l10n \
    git \
    libgtk-3-bin \
    libatk1.0 \
    libatk-bridge2.0 \
    libnss3 \
    thunar \
    adwaita-icon-theme \
    python3-xdg \
    tint2 && \
  echo "**** install Obsidian ****" && \
  if [ -z ${OBSIDIAN_VERSION+x} ]; then \
    OBSIDIAN_VERSION=$(curl -sX GET "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest"| awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  cd /tmp && \
  curl -o \
    /tmp/obsidian.app -L \
    "https://github.com/obsidianmd/obsidian-releases/releases/download/${OBSIDIAN_VERSION}/Obsidian-$(echo ${OBSIDIAN_VERSION} | sed 's/v//g').AppImage" && \
  chmod +x /tmp/obsidian.app && \
  ./obsidian.app --appimage-extract && \
  mv squashfs-root /opt/obsidian && \
  mkdir -p /usr/share/icons/hicolor/48x48/apps && \
  echo "**** convert icons ****" && \
  apt-get install -y --no-install-recommends librsvg2-bin && \
  rsvg-convert -w 48 -h 48 \
    /usr/share/icons/hicolor/scalable/apps/org.xfce.thunar.svg \
    -o /usr/share/icons/hicolor/48x48/apps/thunar.png && \
  apt-get purge -y librsvg2-bin && \
  apt-get autoremove -y && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /config/.cache \
    /config/.launchpadlib \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000

VOLUME /config
