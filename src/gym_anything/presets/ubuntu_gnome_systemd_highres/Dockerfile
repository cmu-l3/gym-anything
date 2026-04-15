FROM ubuntu:24.04

ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8


# Install locale
RUN apt-get update && apt-get install -y --no-install-recommends \
  locales && \
  echo "$LANG UTF-8" >> /etc/locale.gen && \
  locale-gen && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Unminimize to include man pages
RUN yes | unminimize

# Install systemd
RUN apt-get update && apt-get install -y \
  dbus dbus-x11 systemd && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  dpkg-divert --local --rename --add /sbin/udevadm && \
  ln -s /bin/true /sbin/udevadm

VOLUME ["/sys/fs/cgroup"]
STOPSIGNAL SIGRTMIN+3
CMD [ "/sbin/init" ]

# Install GNOME Desktop
RUN apt-get update \
  && apt-get install -y ubuntu-desktop gnome-tweaks \
  && apt-get purge -y --autoremove gnome-initial-setup \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Remove unnecessary system targets
RUN rm -f \
  /lib/systemd/system/local-fs.target.wants/* \
  /lib/systemd/system/sockets.target.wants/*udev* \
  /lib/systemd/system/sockets.target.wants/*initctl* \
  /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
  /lib/systemd/system/systemd-update-utmp* \
  /lib/systemd/system/systemd-resolved.service

# Install TigerVNC server, noVNC, X11 tools, dconf, and media packages
RUN apt-get update \
  && apt-get install -y \
     tigervnc-common tigervnc-scraping-server tigervnc-standalone-server \
     tigervnc-viewer tigervnc-xorg-extension \
     xvfb x11-apps x11-utils xdotool pulseaudio ffmpeg xterm wmctrl \
     net-tools novnc \
     dconf-cli sudo \
  && ln -s /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

COPY tigervnc@.service /etc/systemd/system/tigervnc@.service
RUN systemctl enable tigervnc@:1
EXPOSE 5901

# Create system-wide dconf defaults
RUN mkdir -p /etc/dconf/db/local.d && \
    mkdir -p /etc/dconf/profile

# Create the dconf profile
RUN echo "user-db:user" > /etc/dconf/profile/user && \
    echo "system-db:local" >> /etc/dconf/profile/user

# Create the settings file to disable lock screen
RUN echo "[org/gnome/desktop/screensaver]" > /etc/dconf/db/local.d/01-disable-lock && \
    echo "lock-enabled=false" >> /etc/dconf/db/local.d/01-disable-lock && \
    echo "ubuntu-lock-on-suspend=false" >> /etc/dconf/db/local.d/01-disable-lock && \
    echo "" >> /etc/dconf/db/local.d/01-disable-lock && \
    echo "[org/gnome/desktop/session]" >> /etc/dconf/db/local.d/01-disable-lock && \
    echo "idle-delay=uint32 0" >> /etc/dconf/db/local.d/01-disable-lock



# Update the dconf database
RUN dconf update

# Create unprivileged user 'ga' (matching the service file)
# Remove default ubuntu user if it exists (Ubuntu 24.04 ships with ubuntu:1000)
RUN (userdel -r ubuntu 2>/dev/null || true) && useradd ga -u 1000 -U -d /home/ga -m -s /bin/bash
RUN echo "ga ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/ga" && \
  chmod 440 "/etc/sudoers.d/ga"

USER ga
ENV USER=ga HOME=/home/ga
WORKDIR /home/ga

# Set up VNC
RUN mkdir -p $HOME/.vnc
COPY --chown=ga:ga xstartup $HOME/.vnc/xstartup
RUN chmod +x $HOME/.vnc/xstartup && echo "password" | vncpasswd -f > $HOME/.vnc/passwd && chmod 600 $HOME/.vnc/passwd



# Switch back to root to start systemd
USER root
WORKDIR /workspace


RUN sed -i 's/^enabled=.*/enabled=0/' /etc/default/apport
RUN systemctl stop apport.service 2>/dev/null || service apport stop
RUN systemctl disable apport.service 2>/dev/null || true
RUN systemctl disable --now whoopsie.service 2>/dev/null || true

# Install graphics, imaging, fonts, and development packages
RUN apt-get update && apt-get install -y \
    gimp gimp-data-extras gimp-plugin-registry gimp-gmic \
    gimp-help-en gimp-help-common \
    inkscape imagemagick graphicsmagick exiftool dcraw \
    fonts-liberation fonts-dejavu-extra fonts-noto fonts-hack fonts-firacode \
    build-essential libgimp2.0-dev python3-pip python3-dev \
    wget python3-pil python3-numpy python3-scipy \
    python3-tk \
  && python3 -m pip install --break-system-packages pyautogui \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN sudo apt remove -y update-notifier
