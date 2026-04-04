#!/bin/bash
set -e

echo "=== Installing KStars + INDI Simulator Suite ==="

export DEBIAN_FRONTEND=noninteractive

# ── 1. System utilities ──────────────────────────────────────────────
apt-get update
apt-get install -y \
    software-properties-common \
    scrot wmctrl xdotool imagemagick \
    python3-pip python3-astropy python3-pil \
    wget curl unzip feh

# ── 2. Add INDI PPA and install KStars + INDI + GSC ─────────────────
apt-add-repository -y ppa:mutlaqja/ppa
apt-get update

apt-get install -y \
    kstars-bleeding \
    indi-full \
    gsc

# Verify critical binaries exist
for bin in kstars indiserver indi_simulator_telescope indi_simulator_ccd indi_simulator_focus indi_simulator_wheel; do
    if ! command -v "$bin" &>/dev/null; then
        echo "ERROR: $bin not found after install"
        exit 1
    fi
done

# Verify GSC data directory exists (~309 MB of Hubble Guide Star Catalog)
if [ ! -d /usr/share/GSC ]; then
    echo "WARNING: GSC data not found at /usr/share/GSC — CCD simulator will produce blank images"
fi

# ── 3. Install DS9 (SAOImage astronomical FITS viewer) ───────────────
echo "--- Installing DS9 ---"
apt-get install -y saods9 2>/dev/null || {
    echo "NOTE: saods9 not in apt"
}

# Ensure pillow is available for false color processing
pip3 install pillow 2>/dev/null || true

# ── 4. Ensure qdbus is available (for KStars D-Bus scripting) ────────
# qdbus is used to script KStars: navigate, zoom, enable HiPS overlay,
# and export the sky view as image captures
echo "--- Checking qdbus ---"
if ! command -v qdbus &>/dev/null; then
    apt-get install -y qdbus-qt5 2>/dev/null || \
    apt-get install -y qttools5-dev-tools 2>/dev/null || \
    apt-get install -y libqt5dbus5 2>/dev/null || true
fi

# Verify qdbus
if command -v qdbus &>/dev/null; then
    echo "qdbus available: $(which qdbus)"
else
    echo "WARNING: qdbus not found — D-Bus sky capture may not work"
    echo "  Falling back to scrot-based capture"
fi

echo "=== KStars + INDI installation complete ==="
echo "Installed binaries:"
which kstars indiserver indi_simulator_telescope indi_simulator_ccd
echo "GSC data: $(du -sh /usr/share/GSC 2>/dev/null || echo 'NOT FOUND')"
echo "DS9: $(which ds9 2>/dev/null || echo 'NOT INSTALLED')"
echo "qdbus: $(which qdbus 2>/dev/null || echo 'NOT INSTALLED')"
