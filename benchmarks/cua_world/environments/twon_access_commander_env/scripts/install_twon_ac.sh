#!/bin/bash
set -e

echo "=== Installing 2N Access Commander prerequisites ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Core GUI automation, network, and screenshot tools
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    jq \
    ca-certificates \
    netcat-openbsd \
    python3 \
    python3-pip \
    scrot \
    imagemagick \
    wget \
    net-tools

# System Firefox (not snap — avoids snap profile path complexity)
apt-get install -y firefox || \
    (add-apt-repository -y ppa:mozillateam/ppa && \
     apt-get update && \
     apt-get install -y firefox)

# NSS tools to pre-accept self-signed TLS cert in Firefox
apt-get install -y libnss3-tools

# QEMU/KVM for running 2N Access Commander OVA as nested VM
apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    ovmf \
    bridge-utils \
    cpu-checker || true

# Python deps for REST API verification in verifiers
pip3 install --no-cache-dir requests 2>/dev/null || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== 2N Access Commander prerequisites installed ==="
echo "Firefox: $(firefox --version 2>/dev/null || echo 'check manually')"
echo "QEMU: $(qemu-system-x86_64 --version 2>/dev/null | head -1 || echo 'check manually')"
