#!/bin/bash
set -e

echo "=== Installing GNU Octave and ABRAVIBE Toolbox ==="

export DEBIAN_FRONTEND=noninteractive

# Configure APT for reliability
cat > /etc/apt/apt.conf.d/99custom << 'APT_CONF_EOF'
Acquire::Retries "3";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
APT_CONF_EOF

apt-get update

# Install GNU Octave with GUI and all dependencies
apt-get install -y \
    octave \
    octave-common \
    octave-doc \
    gnuplot \
    gnuplot-x11 \
    liboctave-dev \
    scrot \
    wmctrl \
    xdotool \
    x11-utils \
    imagemagick \
    python3-pip \
    curl \
    wget \
    fonts-dejavu \
    unzip

# Install Octave Forge packages for signal processing
apt-get install -y \
    octave-signal \
    octave-statistics \
    octave-io \
    octave-control || true

echo "=== GNU Octave installed ==="

# =====================================================================
# Install ABRAVIBE toolbox
# =====================================================================
echo "=== Installing ABRAVIBE toolbox ==="

ABRAVIBE_DIR="/usr/share/octave/site/m/abravibe"
mkdir -p "$ABRAVIBE_DIR"

# Copy bundled ABRAVIBE toolbox functions
cp /workspace/data/abravibe_toolbox/*.m "$ABRAVIBE_DIR/"
chmod 644 "$ABRAVIBE_DIR"/*.m

# Add ABRAVIBE to Octave path system-wide
cat > /usr/share/octave/site/m/startup/abravibe_path.m << 'EOF'
% Add ABRAVIBE toolbox to path on startup
addpath('/usr/share/octave/site/m/abravibe');
EOF

echo "ABRAVIBE toolbox installed to $ABRAVIBE_DIR"

# =====================================================================
# Install CWRU bearing dataset (real vibration data)
# =====================================================================
echo "=== Installing CWRU bearing dataset ==="

DATA_DIR="/home/ga/Documents/cwru_data"
mkdir -p "$DATA_DIR"

# Copy CWRU bearing .mat files from mounted data
cp /workspace/data/normal_97.mat "$DATA_DIR/"
cp /workspace/data/ir007_105.mat "$DATA_DIR/"
cp /workspace/data/ball007_118.mat "$DATA_DIR/"
cp /workspace/data/or007_130.mat "$DATA_DIR/"
cp /workspace/data/ir021_209.mat "$DATA_DIR/"

chown -R ga:ga /home/ga/Documents

# Create output directory for plots
mkdir -p /home/ga/plots
chown -R ga:ga /home/ga/plots

echo "=== CWRU bearing dataset installed ==="
echo "=== ABRAVIBE environment installation complete ==="
