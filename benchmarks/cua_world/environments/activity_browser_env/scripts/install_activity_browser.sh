#!/bin/bash
set -e

echo "=== Installing Activity Browser (LCA GUI for Brightway2) ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install system dependencies and GUI automation tools
apt-get install -y \
    wget \
    curl \
    ca-certificates \
    python3-pip \
    python3-dev \
    build-essential \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    libegl1 \
    libxkbcommon0 \
    libxkbcommon-x11-0 \
    libdbus-1-3 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-randr0 \
    libxcb-render-util0 \
    libxcb-xinerama0 \
    libxcb-xfixes0 \
    libxcb-shape0 \
    libxcb-cursor0 \
    x11-utils \
    xauth \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    git

echo "=== Setting up Miniconda ==="

# Check if Miniconda is already installed (base image may have it)
if [ -f /opt/miniconda3/bin/conda ]; then
    echo "Miniconda already installed at /opt/miniconda3"
else
    echo "Installing Miniconda..."
    MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    wget -q "$MINICONDA_URL" -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p /opt/miniconda3
    rm -f /tmp/miniconda.sh
fi

# Add conda to PATH for this script
export PATH="/opt/miniconda3/bin:$PATH"

# Configure conda to use only conda-forge (avoid default channel ToS issues)
/opt/miniconda3/bin/conda config --remove channels defaults 2>/dev/null || true
/opt/miniconda3/bin/conda config --add channels conda-forge 2>/dev/null || true
/opt/miniconda3/bin/conda config --set channel_priority strict 2>/dev/null || true

# Initialize conda for all users (idempotent)
/opt/miniconda3/bin/conda init bash 2>/dev/null || true
if ! grep -q 'miniconda3' /etc/profile.d/conda.sh 2>/dev/null; then
    echo 'export PATH="/opt/miniconda3/bin:$PATH"' >> /etc/profile.d/conda.sh
    chmod +x /etc/profile.d/conda.sh
fi

# Also set up for ga user (idempotent)
su - ga -c "grep -q 'miniconda3' /home/ga/.bashrc 2>/dev/null || echo 'export PATH=\"/opt/miniconda3/bin:\$PATH\"' >> /home/ga/.bashrc"
su - ga -c "/opt/miniconda3/bin/conda init bash 2>/dev/null || true"

echo "=== Creating Conda environment with Activity Browser ==="

# Check if the 'ab' env already exists
if /opt/miniconda3/bin/conda env list | grep -q "^ab "; then
    echo "Conda environment 'ab' already exists"
else
    echo "Creating conda env 'ab' with activity-browser..."
    # Use --override-channels to avoid default channel ToS issues
    /opt/miniconda3/bin/conda create -n ab --override-channels -c conda-forge activity-browser python=3.11 -y
fi

# Fix lxml/libxslt library conflict between conda env and system
# The conda env's libxml2/libxslt must be used, not the system's
echo "=== Fixing lxml/libxslt library linking ==="
/opt/miniconda3/bin/conda install -n ab --override-channels -c conda-forge libxml2 libxslt lxml -y 2>/dev/null || true

# Verify installation
echo "=== Verifying Activity Browser installation ==="
# Must set LD_LIBRARY_PATH to avoid system library conflicts
export LD_LIBRARY_PATH="/opt/miniconda3/envs/ab/lib:$LD_LIBRARY_PATH"
/opt/miniconda3/envs/ab/bin/python -c "import brightway2; print('Brightway2 imported successfully')" || \
    echo "WARNING: brightway2 import check returned non-zero (may still work)"
/opt/miniconda3/envs/ab/bin/python -c "from lxml.builder import ElementMaker; print('lxml works correctly')" || \
    echo "WARNING: lxml import check failed"

if [ -f /opt/miniconda3/envs/ab/bin/activity-browser ]; then
    echo "Activity Browser binary found at /opt/miniconda3/envs/ab/bin/activity-browser"
else
    echo "WARNING: activity-browser binary not found at expected path"
    find /opt/miniconda3/envs/ab/bin/ -name "*activity*" -o -name "*Activity*" 2>/dev/null || true
fi

# Create data directory
mkdir -p /opt/ab_data

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
/opt/miniconda3/bin/conda clean -afy 2>/dev/null || true

echo "=== Activity Browser installation complete ==="
