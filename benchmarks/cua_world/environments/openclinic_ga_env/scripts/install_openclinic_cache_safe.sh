#!/bin/bash
# OpenClinic GA Installation Script (pre_start hook)
# This must complete synchronously so pre_start checkpoints contain a fully
# installed application. Evaluation uses use_cache=True with the default
# pre_start cache level for this Linux QEMU env.

set -euo pipefail

LOG=/home/ga/env_setup_openclinic_download.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

echo "=== Installing OpenClinic GA (pre_start) ==="
echo "Started: $(date)"

export DEBIAN_FRONTEND=noninteractive

INSTALL_MARKER=/tmp/openclinic_install_done
FAIL_MARKER=/tmp/openclinic_install_failed
OPENCLINIC_DEST=/tmp/openclinic.tar.gz
OPENCLINIC_ROOT=/opt/openclinic

is_installed() {
    [ -x "$OPENCLINIC_ROOT/restart_openclinic" ] && \
    [ -x "$OPENCLINIC_ROOT/mysql5/bin/mysql" ] && \
    [ -f "$OPENCLINIC_ROOT/tomcat8/conf/server.xml" ]
}

rm -f "$FAIL_MARKER"

if is_installed; then
    echo "OpenClinic GA already installed at $OPENCLINIC_ROOT"
    touch "$INSTALL_MARKER"
    exit 0
fi

apt-get update

echo "Installing system dependencies..."
apt-get install -y \
    wget \
    curl \
    tar \
    gzip \
    net-tools \
    lsof \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot \
    imagemagick \
    python3-pip \
    python3-pymysql \
    default-mysql-client \
    firefox

pip3 install --no-cache-dir requests pymysql 2>/dev/null || true

DOWNLOADED=0
for URL in \
    "https://sourceforge.net/projects/open-clinic/files/Releases/OpenClinic%20version%205/Linux%20%2864-bit%29/openclinic.ubuntu24.tar.gz/download" \
    "https://sourceforge.net/projects/open-clinic/files/Releases/OpenClinic%20version%205/Linux%20%2864-bit%29/openclinic.ubuntu.tar.gz/download"; do
    echo "Trying download: $URL"
    rm -f "$OPENCLINIC_DEST"
    if wget --timeout=600 --tries=3 -q -O "$OPENCLINIC_DEST" "$URL"; then
        FILESIZE=$(stat -c%s "$OPENCLINIC_DEST" 2>/dev/null || echo 0)
        if [ "$FILESIZE" -gt 10000000 ]; then
            echo "Download succeeded ($((FILESIZE / 1024 / 1024))MB)"
            DOWNLOADED=1
            break
        fi
        echo "Downloaded file too small: ${FILESIZE} bytes"
    else
        echo "Download failed for: $URL"
    fi
done

if [ "$DOWNLOADED" -ne 1 ]; then
    echo "ERROR: Failed to download OpenClinic GA from all known URLs"
    touch "$FAIL_MARKER"
    exit 1
fi

echo "Extracting OpenClinic GA into /opt..."
mkdir -p /opt
rm -rf "$OPENCLINIC_ROOT"
tar -xzf "$OPENCLINIC_DEST" -C /opt/ || tar -xzf "$OPENCLINIC_DEST" -C /opt/ --warning=no-timestamp

if [ ! -d "$OPENCLINIC_ROOT" ]; then
    echo "ERROR: $OPENCLINIC_ROOT directory not found after extraction"
    ls -la /opt/ || true
    touch "$FAIL_MARKER"
    exit 1
fi

echo "Extraction complete"
rm -f "$OPENCLINIC_DEST"

echo "Running OpenClinic setup script..."
cd "$OPENCLINIC_ROOT"
chmod +x setup 2>/dev/null || true
chmod +x ./*.sh 2>/dev/null || true
./setup || echo "WARNING: setup exited non-zero; post_start will verify service readiness"

if ! is_installed; then
    echo "ERROR: OpenClinic install artifacts missing after setup"
    find "$OPENCLINIC_ROOT" -maxdepth 2 -type f | sed -n '1,80p'
    touch "$FAIL_MARKER"
    exit 1
fi

touch "$INSTALL_MARKER"
echo "=== OpenClinic GA install complete $(date) ==="
