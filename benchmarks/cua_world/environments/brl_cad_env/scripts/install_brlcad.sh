#!/bin/bash
set -e

echo "=== Installing BRL-CAD ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -q

# Install runtime dependencies and GUI automation tools
echo "Installing runtime dependencies..."
apt-get install -y \
    wget \
    curl \
    scrot \
    wmctrl \
    xdotool \
    xterm \
    x11-utils \
    imagemagick \
    python3-pip \
    bzip2 \
    libx11-6 \
    libxi6 \
    libxext6 \
    libxcursor1 \
    libxrandr2 \
    libxss1 \
    libgl1-mesa-dri \
    libgl1-mesa-glx 2>/dev/null || true \
    libegl1-mesa \
    libgbm1 \
    mesa-utils \
    libglu1-mesa \
    libfontconfig1 \
    libfreetype6 \
    libtk8.6 \
    libtcl8.6 \
    tk8.6 \
    tcl8.6 \
    libpng16-16 \
    libjpeg-turbo8 2>/dev/null || apt-get install -y libjpeg62-turbo 2>/dev/null || true

# Download BRL-CAD pre-built binary from SourceForge
# Version 7.32.2 is the latest Linux binary distribution available
BRLCAD_VERSION="7.32.2"
BRLCAD_TARBALL="BRL-CAD_${BRLCAD_VERSION}_Linux_x86_64.tar.bz2"
DOWNLOAD_URL="https://sourceforge.net/projects/brlcad/files/BRL-CAD%20for%20Linux/${BRLCAD_VERSION}/${BRLCAD_TARBALL}/download"
INSTALL_DIR="/usr/brlcad"

echo "Downloading BRL-CAD ${BRLCAD_VERSION}..."
cd /tmp

if [ ! -f "/tmp/${BRLCAD_TARBALL}" ]; then
    wget -q --show-progress -L -O "/tmp/${BRLCAD_TARBALL}" "${DOWNLOAD_URL}" || \
    curl -L -o "/tmp/${BRLCAD_TARBALL}" "${DOWNLOAD_URL}" || {
        echo "ERROR: Failed to download BRL-CAD binary"
        exit 1
    }
fi

# Verify download
if [ ! -s "/tmp/${BRLCAD_TARBALL}" ]; then
    echo "ERROR: Downloaded file is empty"
    exit 1
fi
echo "Download size: $(stat -c%s /tmp/${BRLCAD_TARBALL}) bytes"

# Extract the tarball
echo "Extracting BRL-CAD..."
mkdir -p "${INSTALL_DIR}"
cd /tmp
tar xjf "/tmp/${BRLCAD_TARBALL}" || {
    echo "ERROR: Failed to extract BRL-CAD tarball"
    exit 1
}

# BRL-CAD tarballs extract to various structures; find the correct one
EXTRACTED_DIR=""
for candidate in \
    "/tmp/brlcad-${BRLCAD_VERSION}" \
    "/tmp/BRL-CAD_${BRLCAD_VERSION}_Linux_x86_64" \
    "/tmp/usr/brlcad/rel-${BRLCAD_VERSION}" \
    "/tmp/brlcad"; do
    if [ -d "$candidate" ]; then
        EXTRACTED_DIR="$candidate"
        break
    fi
done

# If none of the candidates matched, look for any extracted directory
if [ -z "$EXTRACTED_DIR" ]; then
    # Check if it extracted with a usr/ prefix (common for BRL-CAD)
    if [ -d "/tmp/usr" ]; then
        # Move the entire usr/brlcad tree
        if [ -d "/tmp/usr/brlcad" ]; then
            cp -r /tmp/usr/brlcad/* "${INSTALL_DIR}/" 2>/dev/null || true
            # Find the actual release directory
            BRLCAD_REL=$(find "${INSTALL_DIR}" -maxdepth 1 -type d -name "rel-*" | head -1)
            if [ -n "$BRLCAD_REL" ]; then
                EXTRACTED_DIR="ALREADY_INSTALLED"
                INSTALL_DIR="$BRLCAD_REL"
            fi
        fi
    fi
fi

if [ -z "$EXTRACTED_DIR" ]; then
    echo "WARNING: Could not find extracted directory. Listing /tmp for debug:"
    ls -la /tmp/ | head -20
    echo "Trying to find mged binary..."
    MGED_PATH=$(find /tmp -name "mged" -type f 2>/dev/null | head -1)
    if [ -n "$MGED_PATH" ]; then
        EXTRACTED_DIR=$(dirname $(dirname "$MGED_PATH"))
        echo "Found mged at: $MGED_PATH, using dir: $EXTRACTED_DIR"
    else
        echo "ERROR: Cannot find BRL-CAD installation"
        exit 1
    fi
fi

# Install to final location
if [ "$EXTRACTED_DIR" != "ALREADY_INSTALLED" ]; then
    echo "Installing from ${EXTRACTED_DIR} to ${INSTALL_DIR}..."
    # If extracted dir has a bin/mged, use it directly
    if [ -f "${EXTRACTED_DIR}/bin/mged" ]; then
        cp -r "${EXTRACTED_DIR}"/* "${INSTALL_DIR}/"
    elif [ -d "${EXTRACTED_DIR}/usr/brlcad" ]; then
        # Nested usr/brlcad structure
        NESTED=$(find "${EXTRACTED_DIR}/usr/brlcad" -maxdepth 1 -type d -name "rel-*" | head -1)
        if [ -n "$NESTED" ]; then
            cp -r "${NESTED}"/* "${INSTALL_DIR}/"
        else
            cp -r "${EXTRACTED_DIR}/usr/brlcad"/* "${INSTALL_DIR}/"
        fi
    else
        cp -r "${EXTRACTED_DIR}"/* "${INSTALL_DIR}/"
    fi
fi

# Find the actual BRL-CAD root (might be in a rel-X.Y.Z subdirectory)
BRLCAD_ROOT="${INSTALL_DIR}"
if [ ! -f "${BRLCAD_ROOT}/bin/mged" ]; then
    REL_DIR=$(find "${INSTALL_DIR}" -maxdepth 2 -name "mged" -type f 2>/dev/null | head -1)
    if [ -n "$REL_DIR" ]; then
        BRLCAD_ROOT=$(dirname $(dirname "$REL_DIR"))
    fi
fi

echo "BRL-CAD root: ${BRLCAD_ROOT}"

# Verify MGED binary exists
if [ ! -f "${BRLCAD_ROOT}/bin/mged" ]; then
    echo "ERROR: mged binary not found at ${BRLCAD_ROOT}/bin/mged"
    echo "Contents of ${INSTALL_DIR}:"
    find "${INSTALL_DIR}" -maxdepth 3 -type f -name "mged" 2>/dev/null || echo "No mged found"
    exit 1
fi

# Set up PATH via profile.d so all users/shells get it
cat > /etc/profile.d/brlcad.sh << PATHEOF
export PATH="${BRLCAD_ROOT}/bin:\$PATH"
export LD_LIBRARY_PATH="${BRLCAD_ROOT}/lib:\$LD_LIBRARY_PATH"
export BRLCAD_ROOT="${BRLCAD_ROOT}"
PATHEOF
chmod +x /etc/profile.d/brlcad.sh

# Also add to ga user's bashrc
echo "export PATH=\"${BRLCAD_ROOT}/bin:\$PATH\"" >> /home/ga/.bashrc
echo "export LD_LIBRARY_PATH=\"${BRLCAD_ROOT}/lib:\$LD_LIBRARY_PATH\"" >> /home/ga/.bashrc
echo "export BRLCAD_ROOT=\"${BRLCAD_ROOT}\"" >> /home/ga/.bashrc

# Create symlinks for key binaries
ln -sf "${BRLCAD_ROOT}/bin/mged" /usr/local/bin/mged 2>/dev/null || true
ln -sf "${BRLCAD_ROOT}/bin/rt" /usr/local/bin/rt 2>/dev/null || true
ln -sf "${BRLCAD_ROOT}/bin/g-stl" /usr/local/bin/g-stl 2>/dev/null || true
ln -sf "${BRLCAD_ROOT}/bin/archer" /usr/local/bin/archer 2>/dev/null || true

# Save the root path for later scripts
echo "${BRLCAD_ROOT}" > /tmp/brlcad_root.txt

# Find and verify sample .g database files
DB_DIR=""
for candidate in \
    "${BRLCAD_ROOT}/share/db" \
    "${BRLCAD_ROOT}/share/brlcad/db" \
    "${BRLCAD_ROOT}/share/brlcad/${BRLCAD_VERSION}/db" \
    "${BRLCAD_ROOT}/db"; do
    if [ -d "$candidate" ] && [ -f "$candidate/moss.g" ]; then
        DB_DIR="$candidate"
        break
    fi
done

if [ -z "$DB_DIR" ]; then
    # Search more broadly
    DB_DIR=$(find "${BRLCAD_ROOT}" -type f -name "moss.g" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
fi

if [ -n "$DB_DIR" ]; then
    echo "Sample databases found at: ${DB_DIR}"
    echo "${DB_DIR}" > /tmp/brlcad_db_dir.txt
    echo "Sample .g files:"
    ls -la "${DB_DIR}"/*.g 2>/dev/null | head -20
else
    echo "WARNING: Sample .g database files not found"
    echo "" > /tmp/brlcad_db_dir.txt
fi

# Clean up downloaded tarball
rm -f "/tmp/${BRLCAD_TARBALL}"

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== BRL-CAD installation complete ==="
echo "MGED: ${BRLCAD_ROOT}/bin/mged"
echo "RT: ${BRLCAD_ROOT}/bin/rt"
echo "Sample DB: ${DB_DIR:-not found}"
