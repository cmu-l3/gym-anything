#!/bin/bash
set -e

echo "=== Installing SideFX Houdini ==="

export DEBIAN_FRONTEND=noninteractive

# ================================================================
# 1. INSTALL SYSTEM DEPENDENCIES
# ================================================================
echo "Installing system dependencies..."
apt-get update

# Core X11 / Qt / OpenGL libraries required by Houdini
apt-get install -y \
    wget \
    curl \
    tar \
    gzip \
    python3 \
    python3-pip \
    libtinfo5 \
    libasound2 \
    libcups2 \
    libcurl4 \
    libdbus-1-3 \
    libdrm2 \
    libegl1 \
    libexpat1 \
    libfontconfig1 \
    libgcc-s1 \
    libgl1 \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    libegl1-mesa \
    libgbm1 \
    libglib2.0-0 \
    libglu1-mesa \
    libglx0 \
    libice6 \
    libncursesw6 \
    libnspr4 \
    libnss3 \
    libopengl0 \
    libpci3 \
    libsm6 \
    libxcb-cursor0 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-render-util0 \
    libxcb-xinerama0 \
    libxkbcommon-x11-0 \
    libxmu6 \
    libxt6 \
    libxtst6 \
    libxss1 \
    libxrender1 \
    libxkbcommon0 \
    libxi6 \
    libxext6 \
    libx11-6 \
    libxfixes3 \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libfreetype6 \
    mesa-utils

# GUI automation tools
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    imagemagick \
    ffmpeg

# Verification libraries
pip3 install --quiet opencv-python-headless pillow numpy || true

echo "System dependencies installed."

# ================================================================
# 2. INSTALL DOCKER (needed for Docker image extraction method)
# ================================================================
echo "Installing Docker for Houdini image extraction..."
apt-get install -y docker.io 2>/dev/null || true
systemctl start docker 2>/dev/null || dockerd &
sleep 3

# ================================================================
# 3. FIND OR INSTALL HOUDINI
# ================================================================
echo "Looking for Houdini..."

INSTALL_DIR="/tmp/houdini_install"
mkdir -p "$INSTALL_DIR"
HFS_DIR=""

# Option A: Check if already installed
HFS_DIR=$(find -L /opt -maxdepth 1 -type d -name "hfs*" 2>/dev/null | sort -V | tail -1)
if [ -n "$HFS_DIR" ] && [ -x "$HFS_DIR/bin/hython" ]; then
    echo "Houdini already installed at $HFS_DIR"
fi

# Option B: Check mounted assets for pre-downloaded installer
if [ -z "$HFS_DIR" ] && ls /workspace/assets/houdini-*-linux*.tar.gz 1> /dev/null 2>&1; then
    HOUDINI_TARBALL=$(ls /workspace/assets/houdini-*-linux*.tar.gz | head -1)
    echo "Found pre-downloaded installer: $HOUDINI_TARBALL"
    cd "$INSTALL_DIR"
    tar -xzf "$HOUDINI_TARBALL"
    HOUDINI_EXTRACT_DIR=$(find "$INSTALL_DIR" -maxdepth 1 -type d -name "houdini-*" | head -1)
    if [ -n "$HOUDINI_EXTRACT_DIR" ] && [ -f "$HOUDINI_EXTRACT_DIR/houdini.install" ]; then
        cd "$HOUDINI_EXTRACT_DIR"
        ./houdini.install --auto-install --accept-EULA 2021-10-13 --make-dir --no-license --no-menus --no-local-licensing
        HFS_DIR=$(find -L /opt -maxdepth 1 -type d -name "hfs*" | sort -V | tail -1)
    fi
fi

# Option C: Extract Houdini from Docker Hub image (primary method)
# The hbuild image has Houdini at /opt/houdini/build with a symlink
# /opt/hfs20.5 -> /opt/houdini/build. We must copy the actual directory,
# not the symlink (docker cp only copies the symlink target name).
if [ -z "$HFS_DIR" ] || [ ! -x "$HFS_DIR/bin/hython" ]; then
    echo "Extracting Houdini from Docker image aaronsmithtv/hbuild:20.5.684-base..."
    DOCKER_TAG="20.5.684-base"

    if docker info > /dev/null 2>&1; then
        echo "Pulling Docker image (this may take several minutes)..."
        docker pull "aaronsmithtv/hbuild:${DOCKER_TAG}" 2>&1 | tail -5

        echo "Extracting Houdini files from container..."
        CONTAINER_ID=$(docker create "aaronsmithtv/hbuild:${DOCKER_TAG}")

        # Copy the actual Houdini installation directory (not the symlink)
        mkdir -p /opt
        echo "Copying /opt/houdini from container..."
        docker cp "${CONTAINER_ID}:/opt/houdini" /opt/ 2>/dev/null || {
            echo "Trying fallback: copying entire /opt..."
            mkdir -p /tmp/houdini_extract
            docker cp "${CONTAINER_ID}:/opt/." /tmp/houdini_extract/ 2>/dev/null
            if [ -d /tmp/houdini_extract/houdini ]; then
                cp -a /tmp/houdini_extract/houdini /opt/
            fi
            rm -rf /tmp/houdini_extract
        }

        # Create the standard HFS symlink
        if [ -d /opt/houdini/build ] && [ -x /opt/houdini/build/bin/hython ]; then
            ln -sf /opt/houdini/build /opt/hfs20.5
            echo "Created symlink /opt/hfs20.5 -> /opt/houdini/build"
        fi

        # Copy sesictrl and sesinetd from /usr/lib/sesi (license tools)
        docker cp "${CONTAINER_ID}:/usr/lib/sesi" /usr/lib/sesi 2>/dev/null || true

        # Also copy any shared libraries the container provides
        mkdir -p /tmp/houdini_libs
        docker cp "${CONTAINER_ID}:/usr/lib/." /tmp/houdini_libs/ 2>/dev/null || true
        if [ -d /tmp/houdini_libs ]; then
            cp -an /tmp/houdini_libs/* /usr/lib/ 2>/dev/null || true
            rm -rf /tmp/houdini_libs
        fi

        docker rm "$CONTAINER_ID" > /dev/null 2>&1
        # Clean up docker image to save space
        docker rmi "aaronsmithtv/hbuild:${DOCKER_TAG}" > /dev/null 2>&1 || true

        HFS_DIR=$(find -L /opt -maxdepth 1 -type d -name "hfs*" 2>/dev/null | sort -V | tail -1)
        if [ -n "$HFS_DIR" ] && [ -x "$HFS_DIR/bin/hython" ]; then
            echo "Houdini extracted to: $HFS_DIR"
        else
            echo "WARNING: Docker extraction completed but hython not found"
            ls -la /opt/hfs* 2>/dev/null || echo "No /opt/hfs* directories"
            ls -la /opt/houdini/build/bin/hython 2>/dev/null || echo "No hython at /opt/houdini/build/bin/hython"
        fi
    else
        echo "Docker not available, skipping Docker extraction method"
    fi
fi

# Option D: SideFX API download
if [ -z "$HFS_DIR" ] || [ ! -x "$HFS_DIR/bin/hython" ]; then
    CREDS_FILE="/workspace/config/sidefx_credentials.env"
    if [ -f "$CREDS_FILE" ] || { [ -n "$SIDEFX_CLIENT_ID" ] && [ -n "$SIDEFX_CLIENT_SECRET" ]; }; then
        echo "Attempting SideFX API download..."
        python3 /workspace/scripts/download_houdini.py \
            --credentials-file "$CREDS_FILE" \
            --output-dir "$INSTALL_DIR" \
            --version 20.5 && {
            HOUDINI_TARBALL=$(ls "$INSTALL_DIR"/houdini-*-linux*.tar.gz 2>/dev/null | head -1)
            if [ -n "$HOUDINI_TARBALL" ]; then
                cd "$INSTALL_DIR"
                tar -xzf "$HOUDINI_TARBALL"
                HOUDINI_EXTRACT_DIR=$(find "$INSTALL_DIR" -maxdepth 1 -type d -name "houdini-*" | head -1)
                if [ -n "$HOUDINI_EXTRACT_DIR" ] && [ -f "$HOUDINI_EXTRACT_DIR/houdini.install" ]; then
                    cd "$HOUDINI_EXTRACT_DIR"
                    ./houdini.install --auto-install --accept-EULA 2021-10-13 --make-dir --no-license --no-menus --no-local-licensing
                    HFS_DIR=$(find -L /opt -maxdepth 1 -type d -name "hfs*" | sort -V | tail -1)
                fi
            fi
        }
    fi
fi

# Final check — require at minimum that hython binary exists
if [ -z "$HFS_DIR" ] || [ ! -d "$HFS_DIR" ]; then
    echo "ERROR: Houdini installation failed. No HFS directory found."
    exit 1
fi

if [ ! -x "$HFS_DIR/bin/hython" ]; then
    echo "ERROR: hython binary not found at $HFS_DIR/bin/hython"
    echo "Listing $HFS_DIR/bin/:"
    ls -la "$HFS_DIR/bin/" 2>/dev/null | head -20
    exit 1
fi

echo "Houdini installed to: $HFS_DIR"

# ================================================================
# 4. CONFIGURE ENVIRONMENT
# ================================================================
echo "Configuring Houdini environment..."

# Create profile script for all users
cat > /etc/profile.d/houdini.sh << PROFILE_EOF
# Houdini environment setup
export HFS="$HFS_DIR"
if [ -f "\$HFS/houdini_setup" ]; then
    cd "\$HFS" && source houdini_setup 2>/dev/null && cd - > /dev/null
fi
# Dialog suppression
export HOUDINI_NO_START_PAGE_SPLASH=1
export HOUDINI_ANONYMOUS_STATISTICS=0
export HOUDINI_NOHKEY=1
export HOUDINI_LMINFO_VERBOSE=0
export HOUDINI_PROMPT_ON_CRASHES=0
PROFILE_EOF
chmod 644 /etc/profile.d/houdini.sh

# Source it now for the rest of this script
export HFS="$HFS_DIR"
cd "$HFS_DIR" && source houdini_setup 2>/dev/null && cd / || true

# Create symlinks
ln -sf "$HFS_DIR/bin/houdini" /usr/local/bin/houdini 2>/dev/null || true
ln -sf "$HFS_DIR/bin/hython" /usr/local/bin/hython 2>/dev/null || true
ln -sf "$HFS_DIR/bin/hbatch" /usr/local/bin/hbatch 2>/dev/null || true
ln -sf "$HFS_DIR/bin/hrender" /usr/local/bin/hrender 2>/dev/null || true

# ================================================================
# 4b. LICENSING SETUP
# ================================================================
echo "Setting up Houdini licensing..."

# Start hserver (license proxy daemon)
if [ -x "$HFS_DIR/bin/hserver" ]; then
    "$HFS_DIR/bin/hserver" &
    sleep 2
    echo "hserver started"
fi

# Try to set up licensing using SideFX API credentials if available
CREDS_FILE="/workspace/config/sidefx_credentials.env"
SIDEFX_ID=""
SIDEFX_SECRET=""

if [ -f "$CREDS_FILE" ]; then
    source "$CREDS_FILE" 2>/dev/null || true
    SIDEFX_ID="${SIDEFX_CLIENT_ID:-}"
    SIDEFX_SECRET="${SIDEFX_CLIENT_SECRET:-}"
fi

if [ -n "$SIDEFX_ID" ] && [ -n "$SIDEFX_SECRET" ]; then
    echo "SideFX API credentials found, attempting license setup..."
    # Use sesictrl to log in with API credentials
    SESICTRL=""
    if [ -x /usr/lib/sesi/sesictrl ]; then
        SESICTRL="/usr/lib/sesi/sesictrl"
    elif [ -x "$HFS_DIR/bin/sesictrl" ]; then
        SESICTRL="$HFS_DIR/bin/sesictrl"
    fi

    if [ -n "$SESICTRL" ]; then
        "$SESICTRL" login --clientid "$SIDEFX_ID" --clientsecret "$SIDEFX_SECRET" 2>&1 || \
            echo "sesictrl login failed (credentials may be invalid)"
    else
        echo "sesictrl not found, skipping automated license setup"
    fi
else
    echo "No SideFX API credentials found."
    echo "To enable licensing, create /workspace/config/sidefx_credentials.env with:"
    echo "  SIDEFX_CLIENT_ID=your_client_id"
    echo "  SIDEFX_CLIENT_SECRET=your_client_secret"
    echo "Houdini will launch but show a license dialog until credentials are provided."
fi

# Verify installation
echo "Verifying installation..."
if [ -x "$HFS_DIR/bin/hython" ]; then
    "$HFS_DIR/bin/hython" -c "import hou; print('Houdini version:', hou.applicationVersionString())" 2>&1 || \
        echo "hython import test skipped (licensing may not be configured yet)"
else
    echo "WARNING: hython not found at $HFS_DIR/bin/hython"
fi

# ================================================================
# 5. CREATE DESKTOP ENTRY
# ================================================================
cat > /usr/share/applications/houdini.desktop << DESKTOP_EOF
[Desktop Entry]
Name=Houdini
GenericName=3D VFX Software
Comment=Procedural 3D modeling, animation, and VFX
Exec=$HFS_DIR/bin/houdini %f
Icon=$HFS_DIR/houdini/config/Icons/houdini_logo.svg
Terminal=false
Type=Application
Categories=Graphics;3DGraphics;
MimeType=application/x-houdini;
DESKTOP_EOF

# ================================================================
# 6. CLEANUP
# ================================================================
echo "Cleaning up installation files..."
cd /
rm -rf "$INSTALL_DIR"
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Houdini installation complete ==="
echo "HFS: $HFS_DIR"
