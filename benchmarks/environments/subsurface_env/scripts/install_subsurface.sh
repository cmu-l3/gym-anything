#!/bin/bash
set -euo pipefail

echo "=== Installing Subsurface Dive Log ==="

export DEBIAN_FRONTEND=noninteractive

# Configure APT for reliability
cat > /etc/apt/apt.conf.d/99custom << 'APT_CONF_EOF'
Acquire::Retries "3";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
APT_CONF_EOF

apt-get update

# Install base dependencies and GUI tools
apt-get install -y \
    wget \
    curl \
    software-properties-common \
    gpg \
    apt-transport-https \
    xdotool \
    wmctrl \
    scrot \
    python3 \
    python3-pip \
    xmlstarlet \
    libfuse2 \
    libglib2.0-0 \
    libdbus-1-3

echo "Base dependencies installed."

# =====================================================================
# Install Subsurface
# Primary method: Official Subsurface PPA (stable channel)
# Fallback: AppImage from official downloads
# =====================================================================

SUBSURFACE_INSTALLED=false

# Method 1: Try the stable PPA
echo "Attempting Subsurface installation via PPA..."
if add-apt-repository -y ppa:subsurface/subsurface 2>/dev/null; then
    apt-get update -qq 2>/dev/null || true
    if apt-get install -y subsurface 2>/dev/null; then
        SUBSURFACE_INSTALLED=true
        echo "Subsurface installed via stable PPA."
    fi
fi

# Method 2: Try Ubuntu universe repo (has older version but works)
if [ "$SUBSURFACE_INSTALLED" = "false" ]; then
    echo "PPA failed, trying universe repo..."
    add-apt-repository -y universe 2>/dev/null || true
    apt-get update -qq 2>/dev/null || true
    if apt-get install -y subsurface 2>/dev/null; then
        SUBSURFACE_INSTALLED=true
        echo "Subsurface installed via universe repo."
    fi
fi

# Method 3: AppImage fallback
if [ "$SUBSURFACE_INSTALLED" = "false" ]; then
    echo "Apt install failed, using AppImage..."

    # Try multiple download URLs (version may update)
    APPIMAGE_URLS=(
        "https://subsurface-divelog.org/downloads/Subsurface-6.0.5504-CICD-release.AppImage"
        "https://github.com/subsurface/subsurface/releases/download/v6.0.5504/Subsurface-6.0.5504-x86_64.AppImage"
    )

    APPIMAGE_PATH="/opt/Subsurface.AppImage"
    DOWNLOADED=false

    for url in "${APPIMAGE_URLS[@]}"; do
        if wget -q --timeout=60 -O "$APPIMAGE_PATH" "$url" 2>/dev/null; then
            if [ -s "$APPIMAGE_PATH" ]; then
                DOWNLOADED=true
                echo "AppImage downloaded from $url"
                break
            fi
        fi
    done

    if [ "$DOWNLOADED" = "true" ]; then
        chmod +x "$APPIMAGE_PATH"

        # Create wrapper script that handles FUSE availability
        cat > /usr/local/bin/subsurface << 'WRAPPER_EOF'
#!/bin/bash
export DISPLAY="${DISPLAY:-:1}"
APPIMAGE="/opt/Subsurface.AppImage"

# Try running directly (requires FUSE)
if "$APPIMAGE" "$@" 2>/dev/null; then
    exit 0
fi

# Extract and run if FUSE not available
EXTRACT_DIR="/opt/subsurface-extracted"
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "Extracting AppImage..."
    cd /opt && "$APPIMAGE" --appimage-extract >/dev/null 2>&1 || true
    mv /opt/squashfs-root "$EXTRACT_DIR" 2>/dev/null || true
fi

if [ -f "$EXTRACT_DIR/AppRun" ]; then
    exec "$EXTRACT_DIR/AppRun" "$@"
fi
WRAPPER_EOF
        chmod +x /usr/local/bin/subsurface
        SUBSURFACE_INSTALLED=true
        echo "Subsurface AppImage configured."
    fi
fi

if [ "$SUBSURFACE_INSTALLED" = "false" ]; then
    echo "ERROR: Failed to install Subsurface via all methods."
    exit 1
fi

# =====================================================================
# Download real sample dive data
# Source: Official Subsurface repository - SampleDivesV2.ssrf
# Contains 8 real dives from actual dive computers (OSTC 3, Petrel, etc.)
# Two trips: Sund Rock WA (Dec 2010) and Yellow House WA (Sep 2011)
# =====================================================================
echo "Downloading official Subsurface sample dive data..."
mkdir -p /opt/subsurface_data

SSRF_URLS=(
    "https://raw.githubusercontent.com/subsurface/subsurface/master/dives/SampleDivesV2.ssrf"
    "https://raw.githubusercontent.com/torvalds/subsurface-for-dirk/master/dives/SampleDivesV2.ssrf"
)

SSRF_DOWNLOADED=false
for url in "${SSRF_URLS[@]}"; do
    if wget -q --timeout=60 -O /opt/subsurface_data/SampleDivesV2.ssrf "$url" 2>/dev/null; then
        if [ -s /opt/subsurface_data/SampleDivesV2.ssrf ]; then
            SSRF_DOWNLOADED=true
            echo "Sample data downloaded from $url"
            echo "Sample data size: $(stat -c%s /opt/subsurface_data/SampleDivesV2.ssrf) bytes"
            break
        fi
    fi
done

if [ "$SSRF_DOWNLOADED" = "false" ]; then
    echo "ERROR: Failed to download sample dive data."
    exit 1
fi

chmod 644 /opt/subsurface_data/SampleDivesV2.ssrf

echo "=== Subsurface installation complete ==="
