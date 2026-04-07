#!/bin/bash
set -e

echo "=== Installing PEBL (Psychology Experiment Building Language) ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install build dependencies for PEBL2
# PEBL Makefile uses clang/clang++ by default
apt-get install -y \
    build-essential \
    g++ \
    clang \
    make \
    flex \
    bison \
    git \
    wget \
    libsdl2-dev \
    libsdl2-image-dev \
    libsdl2-ttf-dev \
    libsdl2-net-dev \
    libsdl2-gfx-dev \
    libsdl2-mixer-dev \
    libcurl4-openssl-dev \
    libpng-dev \
    libsdl2-2.0-0 \
    libsdl2-image-2.0-0 \
    libsdl2-ttf-2.0-0 \
    libsdl2-net-2.0-0 \
    libsdl2-gfx-1.0-0 \
    libsdl2-mixer-2.0-0

# Install GUI and testing tools
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    gedit \
    libreoffice-calc \
    dbus-x11

# Clone PEBL from GitHub
echo "=== Cloning PEBL from GitHub ==="
if [ ! -d /opt/pebl ]; then
    git clone --depth 1 https://github.com/stmueller/pebl.git /opt/pebl
fi

# Apply patches for Ubuntu 22.04 SDL2_ttf compatibility
echo "=== Patching PEBL for SDL2_ttf compatibility ==="
cd /opt/pebl

# Patch 1: Add missing GetTTFFont() accessor to PlatformFont.h
if ! grep -q "GetTTFFont" src/platforms/sdl/PlatformFont.h; then
    sed -i '/unsigned int GetPosition/a\    TTF_Font * GetTTFFont() const { return mTTF_Font; }' \
        src/platforms/sdl/PlatformFont.h
    echo "Patched PlatformFont.h: added GetTTFFont() accessor"
fi

# Patch 2: Guard SDL_ttf 2.20+ APIs (TTF_SetFontScriptName, TTF_DIRECTION_*)
# These are not available in SDL2_ttf < 2.20 (Ubuntu 22.04 ships 2.0.18)
# Patch 3: Add missing FORMATTED property to PTextBox (bug in PEBL 2.3 master)
if ! grep -q "FORMATTED" src/objects/PTextBox.cpp; then
    sed -i '/InitializeProperty("TEXTCOMPLETE"/a\    InitializeProperty("FORMATTED",Variant(0));' \
        src/objects/PTextBox.cpp
    echo "Patched PTextBox.cpp: added FORMATTED property initialization"
fi

python3 << 'PATCHEOF'
with open("src/platforms/sdl/PlatformFont.cpp", "r") as f:
    lines = f.readlines()

new_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    if "TTF_SetFontScriptName" in line and "#if" not in lines[max(0,i-1)]:
        new_lines.append("#if SDL_TTF_COMPILEDVERSION >= SDL_VERSIONNUM(2,20,0)\n")
        new_lines.append(line)
        i += 1
        # Consume until we find TTF_DIRECTION_LTR and its closing brace
        while i < len(lines):
            new_lines.append(lines[i])
            if "TTF_DIRECTION_LTR" in lines[i]:
                i += 1
                # Get closing braces
                while i < len(lines) and lines[i].strip() in ["}", ")", ""]:
                    new_lines.append(lines[i])
                    i += 1
                    if lines[i-1].strip() == "}":
                        break
                new_lines.append("#endif\n")
                break
            i += 1
    else:
        new_lines.append(line)
        i += 1

with open("src/platforms/sdl/PlatformFont.cpp", "w") as f:
    f.writelines(new_lines)
print("Patched PlatformFont.cpp: guarded SDL_ttf 2.20+ APIs")
PATCHEOF

# Build PEBL from source
echo "=== Building PEBL ==="
make -j$(nproc) main 2>&1 || {
    echo "Build failed, attempting clean build..."
    make clean 2>/dev/null || true
    make -j$(nproc) main 2>&1
}

# Install PEBL system-wide
echo "=== Installing PEBL system-wide ==="
make install 2>&1 || {
    echo "make install failed, setting up manually..."
    mkdir -p /usr/local/bin
    if [ -f /opt/pebl/bin/pebl2 ]; then
        ln -sf /opt/pebl/bin/pebl2 /usr/local/bin/pebl2
    fi
}

# Verify binary exists
if ! command -v pebl2 &>/dev/null && [ ! -f /usr/local/bin/pebl2 ]; then
    echo "ERROR: PEBL binary not found after install"
    exit 1
fi

echo "PEBL binary installed: $(which pebl2 2>/dev/null || echo /usr/local/bin/pebl2)"

# Create wrapper script
cat > /usr/local/bin/run-pebl << 'PEBLWRAPPER'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
# Use software renderer to avoid OpenGL crashes in VNC/QEMU environments
export SDL_RENDER_DRIVER=software
if [ -f /usr/local/bin/pebl2 ]; then
    exec /usr/local/bin/pebl2 "$@"
elif [ -f /usr/local/pebl2/bin/pebl2 ]; then
    exec /usr/local/pebl2/bin/pebl2 "$@"
elif [ -f /opt/pebl/bin/pebl2 ]; then
    exec /opt/pebl/bin/pebl2 "$@"
else
    echo "ERROR: PEBL binary not found"
    exit 1
fi
PEBLWRAPPER
chmod +x /usr/local/bin/run-pebl

# Set up battery directory for the ga user
BATTERY_DIR=""
if [ -d /usr/local/pebl2/battery ]; then
    BATTERY_DIR="/usr/local/pebl2/battery"
elif [ -d /opt/pebl/battery ]; then
    BATTERY_DIR="/opt/pebl/battery"
fi

mkdir -p /home/ga/pebl
if [ -n "$BATTERY_DIR" ]; then
    # Copy battery to a writable location (PEBL needs write access for data output)
    cp -r "$BATTERY_DIR" /home/ga/pebl/battery
    echo "Battery directory copied: $BATTERY_DIR -> /home/ga/pebl/battery"
fi

# Set ownership
chown -R ga:ga /home/ga/pebl 2>/dev/null || true

echo "=== PEBL installation complete ==="
echo "PEBL binary: $(which pebl2 2>/dev/null || echo /usr/local/bin/pebl2)"
echo "Battery: ${BATTERY_DIR:-/home/ga/pebl/battery}"
