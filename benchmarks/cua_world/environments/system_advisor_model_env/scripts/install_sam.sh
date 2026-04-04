#!/bin/bash
# Do NOT use set -e: SAM installer may return non-zero on success

echo "=== Installing NREL System Advisor Model (SAM) ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install system dependencies for SAM GUI
apt-get install -y \
    wget \
    curl \
    ca-certificates \
    libgtk-3-0 \
    libglib2.0-0 \
    libx11-6 \
    libxext6 \
    libxrender1 \
    libxtst6 \
    libxi6 \
    libfontconfig1 \
    libfreetype6 \
    libxcursor1 \
    libxrandr2 \
    libxinerama1 \
    libgl1-mesa-glx \
    libglu1-mesa \
    libasound2 \
    libdbus-1-3 \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    python3-venv \
    jq

# ============================================================
# Install PySAM (Python SDK for SAM)
# PySAM is the recommended way to programmatically create
# SAM projects, run simulations, and extract results
# ============================================================
echo "Installing PySAM Python package..."
pip3 install NREL-PySAM --break-system-packages 2>/dev/null || \
    pip3 install NREL-PySAM || true

# Verify PySAM installation
python3 -c "import PySAM; print('PySAM version:', PySAM.__version__)" 2>/dev/null || {
    echo "WARNING: PySAM import failed, trying alternative install..."
    pip3 install nrel-pysam --break-system-packages 2>/dev/null || \
        pip3 install nrel-pysam || true
}

python3 -c "import PySAM.Pvwattsv8; print('PySAM Pvwattsv8 module available')" 2>/dev/null || \
    echo "WARNING: PySAM Pvwattsv8 not available"

# ============================================================
# Download and Install SAM Desktop Application
# ============================================================
SAM_VERSION="2024-12-12"
SAM_URL="https://samrepo.nrelcloud.org/beta-releases/sam-linux-${SAM_VERSION}.run"
SAM_INSTALLER="/tmp/sam-linux-${SAM_VERSION}.run"

echo "Downloading SAM ${SAM_VERSION}..."
wget --timeout=120 -O "$SAM_INSTALLER" "$SAM_URL" || {
    echo "Failed to download from beta releases, trying alternative URL..."
    SAM_URL="https://samrepo.nrelcloud.org/downloads/sam-linux-${SAM_VERSION}.run"
    wget --timeout=120 -O "$SAM_INSTALLER" "$SAM_URL" || {
        echo "Failed second URL, trying GitHub releases..."
        SAM_URL="https://github.com/NREL/SAM/releases/download/2024.12.12/sam-linux-${SAM_VERSION}.run"
        wget --timeout=120 -O "$SAM_INSTALLER" "$SAM_URL" || {
            echo "WARNING: Could not download SAM desktop application"
            echo "PySAM is still available for scripting tasks"
        }
    }
}

SAM_DIR=""

if [ -f "$SAM_INSTALLER" ]; then
    chmod +x "$SAM_INSTALLER"

    echo "Installing SAM desktop application..."
    mkdir -p /opt/SAM

    # Run installer - pipe empty string to accept defaults
    echo "" | "$SAM_INSTALLER" 2>&1 | tee /tmp/sam_install.log || true

    # Find SAM installation directory
    # The installer may create versioned subdirectories
    if [ -d "/opt/SAM/2024.12.12" ]; then
        SAM_DIR="/opt/SAM/2024.12.12"
    elif [ -d "/opt/SAM/2025.4.16" ]; then
        SAM_DIR="/opt/SAM/2025.4.16"
    else
        # Search for any SAM binary
        SAM_BINARY=$(find /opt/SAM -name "sam.bin" -o -name "SAM" -o -name "sam" 2>/dev/null | head -1)
        if [ -n "$SAM_BINARY" ]; then
            SAM_DIR=$(dirname "$SAM_BINARY")
        fi

        # Also check home directory (some versions install there by default)
        if [ -z "$SAM_DIR" ]; then
            SAM_BINARY=$(find /home -name "sam.bin" -o -name "SAM" 2>/dev/null | head -1)
            if [ -n "$SAM_BINARY" ]; then
                SAM_DIR=$(dirname "$SAM_BINARY")
            fi
        fi
    fi

    if [ -n "$SAM_DIR" ]; then
        ln -sf "$SAM_DIR" /opt/SAM/current
        echo "SAM installed to: $SAM_DIR"
        ls -la "$SAM_DIR/" | head -20

        # Create symlinks for easy access
        for binary in sam sam.bin SAM; do
            if [ -x "$SAM_DIR/$binary" ]; then
                ln -sf "$SAM_DIR/$binary" /usr/local/bin/sam
                echo "Linked $SAM_DIR/$binary -> /usr/local/bin/sam"
                break
            fi
        done

        # Also link SDKtool if available
        SDKTOOL=$(find "$SAM_DIR" -name "SDKtool" -type f 2>/dev/null | head -1)
        if [ -n "$SDKTOOL" ]; then
            ln -sf "$SDKTOOL" /usr/local/bin/SDKtool
            echo "SDKtool available at: $SDKTOOL"
        fi

        # Record SAM directory for other scripts
        echo "$SAM_DIR" > /opt/SAM/sam_dir.txt
    else
        echo "WARNING: SAM binary not found after installation"
        echo "Contents of /opt/SAM:"
        find /opt/SAM -maxdepth 3 -ls 2>/dev/null || true
    fi

    # Clean up installer
    rm -f "$SAM_INSTALLER"
else
    echo "WARNING: SAM installer not downloaded. Using PySAM only."
fi

# ============================================================
# Download Phoenix, AZ TMY weather data for tasks
# ============================================================
echo "Setting up weather data for tasks..."
WEATHER_DIR="/home/ga/SAM_Weather_Data"
mkdir -p "$WEATHER_DIR"

# SAM installation includes weather data - find and link it
if [ -n "$SAM_DIR" ]; then
    WEATHER_FOUND=$(find "$SAM_DIR" -name "*phoenix*" -o -name "*Phoenix*" 2>/dev/null | head -1)
    if [ -n "$WEATHER_FOUND" ]; then
        cp "$WEATHER_FOUND" "$WEATHER_DIR/phoenix_az_tmy.csv" 2>/dev/null || true
        echo "Found Phoenix weather data: $WEATHER_FOUND"
    fi

    # Also find any solar_resource directory
    SOLAR_RES=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)
    if [ -n "$SOLAR_RES" ]; then
        echo "Solar resource directory: $SOLAR_RES"
        ls "$SOLAR_RES/" | head -10
    fi

    # Find wind resource directory
    WIND_RES=$(find "$SAM_DIR" -type d -name "wind_resource" 2>/dev/null | head -1)
    if [ -n "$WIND_RES" ]; then
        echo "Wind resource directory: $WIND_RES"
        ls "$WIND_RES/" | head -10
    fi
fi

chown -R ga:ga "$WEATHER_DIR"

# ============================================================
# Kill any SAM GUI that may have auto-launched during installation
# The .run installer sometimes launches SAM with a registration dialog
# ============================================================
killall -9 sam sam.bin SAM 2>/dev/null || true
sleep 1

# Prevent SAM from auto-starting on login
rm -f /home/ga/.config/autostart/sam*.desktop 2>/dev/null || true
rm -f /etc/xdg/autostart/sam*.desktop 2>/dev/null || true

# ============================================================
# Final verification
# ============================================================
echo ""
echo "=== Installation Summary ==="
echo "PySAM: $(python3 -c 'import PySAM; print(PySAM.__version__)' 2>/dev/null || echo 'NOT INSTALLED')"
echo "SAM Desktop: $(ls /usr/local/bin/sam 2>/dev/null && echo 'INSTALLED' || echo 'NOT INSTALLED')"
echo "SDKtool: $(ls /usr/local/bin/SDKtool 2>/dev/null && echo 'INSTALLED' || echo 'NOT INSTALLED')"
echo "SAM Directory: ${SAM_DIR:-NOT FOUND}"
echo ""
echo "=== SAM installation complete ==="
