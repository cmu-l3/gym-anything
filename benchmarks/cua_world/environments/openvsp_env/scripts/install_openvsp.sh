#!/bin/bash
set -e

echo "=== Installing OpenVSP ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install GUI automation and utility tools
apt-get install -y \
    scrot wmctrl xdotool imagemagick \
    x11-utils xclip \
    python3-pip \
    curl wget \
    libfuse2 \
    jq

# Install known OpenVSP dependencies proactively
apt-get install -y \
    libcminpack1 \
    libglew2.2 \
    libfltk1.3 \
    libfltk-gl1.3 \
    libglm-dev \
    freeglut3 \
    libxml2 \
    2>/dev/null || true

# Try to get a newer libstdc++ from toolchain PPA if needed
add-apt-repository -y ppa:ubuntu-toolchain-r/test 2>/dev/null || true
apt-get update 2>/dev/null || true
apt-get install -y libstdc++6 2>/dev/null || true

cd /tmp

# Download OpenVSP .deb package for Ubuntu 22.04
# Try multiple versions in order of preference (newer first, but compatible with Ubuntu 22.04)
INSTALLED=false
for OPENVSP_VERSION in "3.48.0" "3.47.0" "3.46.0" "3.45.0" "3.43.0"; do
    OPENVSP_DEB="OpenVSP-${OPENVSP_VERSION}-Ubuntu-22.04_amd64.deb"

    # Try current directory first, then old directory
    for URL_PATH in "zips/current/linux" "zips/old/linux"; do
        OPENVSP_URL="https://openvsp.org/download.php?file=${URL_PATH}/${OPENVSP_DEB}"
        echo "Trying OpenVSP ${OPENVSP_VERSION} from ${URL_PATH}..."
        if wget -q "${OPENVSP_URL}" -O "/tmp/${OPENVSP_DEB}" 2>/dev/null; then
            # Check file is valid (not empty or error page)
            FILE_SIZE=$(stat -c%s "/tmp/${OPENVSP_DEB}" 2>/dev/null || echo 0)
            if [ "$FILE_SIZE" -gt 1000000 ]; then
                echo "Downloaded ${OPENVSP_DEB} (${FILE_SIZE} bytes)"
                # Try to install
                if dpkg -i "/tmp/${OPENVSP_DEB}" 2>/dev/null; then
                    echo "OpenVSP ${OPENVSP_VERSION} installed successfully"
                    INSTALLED=true
                    break 2
                else
                    echo "dpkg failed, trying apt-get install -f..."
                    if apt-get install -f -y 2>/dev/null; then
                        # Check if openvsp is actually configured
                        if dpkg -s openvsp 2>/dev/null | grep -q "Status: install ok installed"; then
                            echo "OpenVSP ${OPENVSP_VERSION} installed via apt-get -f"
                            INSTALLED=true
                            break 2
                        fi
                    fi
                    # If dependencies couldn't be satisfied, remove and try next version
                    dpkg --remove --force-remove-reinstreq openvsp 2>/dev/null || true
                fi
            else
                echo "Downloaded file too small (${FILE_SIZE} bytes), likely error page"
            fi
        fi
        rm -f "/tmp/${OPENVSP_DEB}" 2>/dev/null || true
    done
done

if [ "$INSTALLED" != "true" ]; then
    echo "ERROR: Could not install any version of OpenVSP via .deb"
    echo "Attempting to build from source as fallback..."

    # Build from source as last resort
    apt-get install -y \
        cmake g++ swig \
        libxml2-dev \
        libfltk1.3-dev \
        libcminpack-dev \
        libglew-dev \
        libglm-dev \
        freeglut3-dev \
        libeigen3-dev \
        libcpptest-dev \
        2>/dev/null || true

    cd /tmp
    if wget -q "https://github.com/OpenVSP/OpenVSP/archive/refs/tags/OpenVSP_3.41.2.tar.gz" -O openvsp-src.tar.gz 2>/dev/null; then
        tar xzf openvsp-src.tar.gz
        cd OpenVSP-OpenVSP_3.41.2
        mkdir -p build && cd build
        cmake ../src -DCMAKE_BUILD_TYPE=Release 2>/dev/null || true
        make -j$(nproc) 2>/dev/null || true
        make install 2>/dev/null || true
        cd /tmp
        rm -rf OpenVSP-OpenVSP_3.41.2 openvsp-src.tar.gz
        OPENVSP_VERSION="3.41.2-source"
    fi
fi

# Verify installation - find the OpenVSP binary
VSPBIN=""
for candidate in /usr/bin/vsp /usr/local/bin/vsp /usr/local/bin/openvsp /opt/OpenVSP/vsp; do
    if [ -x "$candidate" ]; then
        VSPBIN="$candidate"
        break
    fi
done

# Broader search
if [ -z "$VSPBIN" ]; then
    VSPBIN=$(find /usr /opt -name "vsp" -type f -executable 2>/dev/null | head -1)
fi

# Search installed package files
if [ -z "$VSPBIN" ]; then
    PKG_NAME=$(dpkg --list 2>/dev/null | grep -i openvsp | awk '{print $2}' | head -1)
    if [ -n "$PKG_NAME" ]; then
        VSPBIN=$(dpkg -L "$PKG_NAME" 2>/dev/null | grep -E '/vsp$' | head -1)
    fi
fi

if [ -n "$VSPBIN" ]; then
    echo "Found OpenVSP binary at: $VSPBIN"
    ln -sf "$VSPBIN" /usr/local/bin/openvsp 2>/dev/null || true
    # Store path for other scripts
    echo "$VSPBIN" > /tmp/openvsp_bin_path
else
    echo "WARNING: Could not find OpenVSP binary after installation"
    echo "Installed packages:"
    dpkg --list | grep -i vsp || true
    echo "Searching for vsp executables:"
    find /usr /opt -name "*vsp*" -type f -executable 2>/dev/null | head -20
fi

# Create directory for sample models
mkdir -p /opt/openvsp_models
cp /workspace/data/*.vsp3 /opt/openvsp_models/ 2>/dev/null || true
chmod -R 755 /opt/openvsp_models
chmod 644 /opt/openvsp_models/*.vsp3 2>/dev/null || true

# Clean up
rm -f /tmp/OpenVSP-*.deb 2>/dev/null || true

echo "=== OpenVSP installation complete ==="
echo "Installed OpenVSP version: ${OPENVSP_VERSION}"
