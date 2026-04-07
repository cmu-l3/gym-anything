#!/bin/bash
set -e

echo "=== Installing Blender + BlenderBIM (Bonsai) ==="

export DEBIAN_FRONTEND=noninteractive

# ── 1. System dependencies ──────────────────────────────────────────────
apt-get update
apt-get install -y \
    wget curl unzip ca-certificates \
    libgl1-mesa-glx libgl1-mesa-dri mesa-utils \
    libegl1-mesa libgles2-mesa \
    libxi6 libxkbcommon0 libxrender1 libxxf86vm1 libxfixes3 libxcursor1 \
    libsm6 libice6 libx11-6 libxext6 libxrandr2 libxinerama1 \
    libfreetype6 libfontconfig1 libjpeg-turbo8 libpng16-16 libtiff5 \
    libglib2.0-0 libglu1-mesa libdrm2 libgbm1 \
    libvulkan1 mesa-vulkan-drivers \
    xdotool wmctrl x11-utils xclip scrot imagemagick \
    python3 python3-pip \
    ffmpeg

echo "=== System dependencies installed ==="

# ── 2. Install Blender 4.2.4 LTS ────────────────────────────────────────
BLENDER_VERSION="4.2.4"
BLENDER_URL="https://download.blender.org/release/Blender4.2/blender-${BLENDER_VERSION}-linux-x64.tar.xz"
BLENDER_MIRROR="https://mirror.clarkson.edu/blender/release/Blender4.2/blender-${BLENDER_VERSION}-linux-x64.tar.xz"

echo "=== Downloading Blender ${BLENDER_VERSION} ==="
cd /tmp
for url in "$BLENDER_URL" "$BLENDER_MIRROR"; do
    echo "Trying: $url"
    if wget -q --show-progress "$url" -O blender.tar.xz; then
        echo "Download succeeded from: $url"
        break
    fi
    echo "Failed, trying next mirror..."
done

if [ ! -f /tmp/blender.tar.xz ] || [ ! -s /tmp/blender.tar.xz ]; then
    echo "ERROR: Failed to download Blender"
    exit 1
fi

echo "=== Extracting Blender ==="
tar xf /tmp/blender.tar.xz -C /opt/
BLENDER_DIR=$(ls -d /opt/blender-${BLENDER_VERSION}* 2>/dev/null | head -1)
if [ -z "$BLENDER_DIR" ]; then
    echo "ERROR: Blender extraction failed"
    exit 1
fi
ln -sf "$BLENDER_DIR" /opt/blender
ln -sf /opt/blender/blender /usr/local/bin/blender
rm -f /tmp/blender.tar.xz

# Verify Blender binary
if ! /opt/blender/blender --version; then
    echo "ERROR: Blender binary not functional"
    exit 1
fi
echo "=== Blender ${BLENDER_VERSION} installed ==="

# Detect Blender's Python version
BLENDER_PYTHON=$(/opt/blender/blender --background --python-expr "import sys; print(sys.executable)" 2>/dev/null | grep -E '^/' | head -1)
BLENDER_PY_VER=$(/opt/blender/blender --background --python-expr "import sys; print(f'py{sys.version_info.major}{sys.version_info.minor}')" 2>/dev/null | grep -E '^py' | head -1)
echo "Blender Python: $BLENDER_PYTHON ($BLENDER_PY_VER)"

# ── 3. Install Bonsai (BlenderBIM) extension ────────────────────────────
# Find matching Bonsai release for Blender's Python version via GitHub API
echo "=== Downloading Bonsai (BlenderBIM) extension ==="

BONSAI_URL1="https://github.com/IfcOpenShell/IfcOpenShell/releases/download/bonsai-0.8.5-alpha2603061409/bonsai_${BLENDER_PY_VER}-0.8.5-alpha260306-linux-x64.zip"
BONSAI_URL2="https://github.com/IfcOpenShell/IfcOpenShell/releases/download/bonsai-0.8.5-alpha2603030748/bonsai_${BLENDER_PY_VER}-0.8.5-alpha260303-linux-x64.zip"
BONSAI_URL3="https://github.com/IfcOpenShell/IfcOpenShell/releases/download/bonsai-0.8.5-alpha2602271158/bonsai_${BLENDER_PY_VER}-0.8.5-alpha260227-linux-x64.zip"

BONSAI_DOWNLOADED=false
for url in "$BONSAI_URL1" "$BONSAI_URL2" "$BONSAI_URL3"; do
    echo "Trying: $url"
    if wget -q "$url" -O /home/ga/bonsai.zip && [ -s /home/ga/bonsai.zip ]; then
        file /home/ga/bonsai.zip | grep -q "Zip archive" && BONSAI_DOWNLOADED=true && break
        echo "Downloaded file is not a valid ZIP"
        rm -f /home/ga/bonsai.zip
    fi
    echo "Failed, trying next URL..."
done

if [ "$BONSAI_DOWNLOADED" = "true" ]; then
    echo "=== Installing Bonsai extension ==="

    # Install extension WITHOUT --enable (avoids partial registration conflicts)
    /opt/blender/blender --command extension install-file -r user_default /home/ga/bonsai.zip 2>&1 || true

    # Install all bundled wheels into Blender's Python
    BLENDER_MAJOR_MINOR=$(echo "$BLENDER_VERSION" | cut -d. -f1,2)
    WHEELS_DIR="/home/ga/.config/blender/${BLENDER_MAJOR_MINOR}/extensions/user_default/bonsai/wheels"
    if [ -d "$WHEELS_DIR" ]; then
        echo "Installing Bonsai wheel dependencies..."
        "$BLENDER_PYTHON" -m pip install --no-deps "$WHEELS_DIR"/*.whl 2>&1 || true
    fi

    # Install tzfpy (native dependency not bundled as compatible wheel)
    "$BLENDER_PYTHON" -m pip install tzfpy 2>&1 || true
    # Copy tzfpy to extensions site-packages (Blender uses a separate path)
    EXT_SP="/home/ga/.config/blender/${BLENDER_MAJOR_MINOR}/extensions/.local/lib/python3.11/site-packages"
    mkdir -p "$EXT_SP"
    TZFPY_SRC=$(python3 -c "import tzfpy; import os; print(os.path.dirname(tzfpy.__file__))" 2>/dev/null || \
                "$BLENDER_PYTHON" -c "import tzfpy; import os; print(os.path.dirname(tzfpy.__file__))" 2>/dev/null || \
                echo "/home/ga/.local/lib/python3.11/site-packages/tzfpy")
    if [ -d "$TZFPY_SRC" ]; then
        cp -r "$TZFPY_SRC" "$EXT_SP/"
        echo "tzfpy copied to $EXT_SP"
    fi

    # Fix permissions on pyradiance binaries (needed for extension registration)
    PYRAD_BIN="$($BLENDER_PYTHON -c "import pyradiance; import os; print(os.path.join(os.path.dirname(pyradiance.__file__), 'bin'))" 2>/dev/null || echo "")"
    if [ -n "$PYRAD_BIN" ] && [ -d "$PYRAD_BIN" ]; then
        chmod +x "$PYRAD_BIN"/* 2>/dev/null || true
        echo "Fixed pyradiance binary permissions"
    fi

    # Enable extension in a clean Blender session (all deps installed first)
    /opt/blender/blender --background --python-expr "
import bpy
try:
    bpy.ops.preferences.addon_enable(module='bl_ext.user_default.bonsai')
    bpy.ops.wm.save_userpref()
    print('Bonsai extension enabled and preferences saved')
except Exception as e:
    print(f'Enable attempt: {e}')
" 2>&1 || true

    rm -f /home/ga/bonsai.zip
    chown -R ga:ga /home/ga/.config
else
    echo "WARNING: Could not download Bonsai extension"
    "$BLENDER_PYTHON" -m pip install ifcopenshell 2>/dev/null || true
fi

echo "=== Bonsai (BlenderBIM) installation complete ==="

# ── 4. Download real IFC building models ─────────────────────────────────
echo "=== Downloading real IFC building models ==="
mkdir -p /home/ga/IFCModels /home/ga/BIMProjects
chown ga:ga /home/ga/IFCModels /home/ga/BIMProjects

# FZK-Haus: Real IFC4 building model from Karlsruhe Institute of Technology (KIT)
# A two-story residential house with 13 walls, 5 doors, 11 windows, 4 slabs
FZK_URL="https://www.ifcwiki.org/images/e/e3/AC20-FZK-Haus.ifc"
echo "Downloading FZK-Haus IFC model..."
if wget -q "$FZK_URL" -O /home/ga/IFCModels/fzk_haus.ifc && [ -s /home/ga/IFCModels/fzk_haus.ifc ]; then
    echo "FZK-Haus model downloaded: $(wc -c < /home/ga/IFCModels/fzk_haus.ifc) bytes"
else
    echo "WARNING: FZK-Haus download failed"
fi

chown -R ga:ga /home/ga/IFCModels /home/ga/BIMProjects

# ── 5. Install Python verification tools ──────────────────────────────────
pip3 install --break-system-packages pillow opencv-python-headless numpy 2>/dev/null || \
pip3 install pillow opencv-python-headless numpy 2>/dev/null || true

# ── 6. Create desktop entry ───────────────────────────────────────────────
cat > /usr/share/applications/blender-bim.desktop << 'EOF'
[Desktop Entry]
Name=BlenderBIM (Bonsai)
Comment=BIM modeling with Blender and Bonsai
Exec=/opt/blender/blender
Icon=/opt/blender/blender.svg
Type=Application
Categories=Graphics;3DGraphics;Engineering;
Terminal=false
EOF

# ── 7. Create Blender config directories ──────────────────────────────────
BLENDER_MAJOR_MINOR=$(echo "$BLENDER_VERSION" | cut -d. -f1,2)
mkdir -p "/home/ga/.config/blender/${BLENDER_MAJOR_MINOR}/config"
mkdir -p "/home/ga/.config/blender/${BLENDER_MAJOR_MINOR}/scripts/addons"
mkdir -p "/home/ga/.config/blender/${BLENDER_MAJOR_MINOR}/extensions/user_default"
chown -R ga:ga /home/ga/.config

echo "=== BlenderBIM (Bonsai) installation complete ==="
