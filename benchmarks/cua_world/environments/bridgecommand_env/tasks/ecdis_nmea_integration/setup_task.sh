#!/bin/bash
set -e
echo "=== Setting up ECDIS NMEA Integration Task ==="

# Define paths
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
BC_CONFIG_FILE="$BC_CONFIG_DIR/bc5.ini"
DOCS_DIR="/home/ga/Documents"
DESKTOP_DIR="/home/ga/Desktop"

# Create directories
mkdir -p "$BC_CONFIG_DIR"
mkdir -p "$DOCS_DIR"
mkdir -p "$DESKTOP_DIR"

# 1. Reset Bridge Command Configuration to Defaults (Disable NMEA)
# We want to ensure the agent has to explicitly configure it.
# If a config exists, ensure NMEA settings are cleared/reset.
if [ -f "$BC_CONFIG_FILE" ]; then
    echo "Resetting existing configuration..."
    # Use sed to disable NMEA or set to defaults
    sed -i 's/^NMEA_UDPAddress=.*/NMEA_UDPAddress=/' "$BC_CONFIG_FILE"
    sed -i 's/^NMEA_UDPPort=.*/NMEA_UDPPort=/' "$BC_CONFIG_FILE"
else
    echo "Creating default configuration..."
    # Copy from template if available, otherwise create minimal
    if [ -f /workspace/config/bc5.ini ]; then
        cp /workspace/config/bc5.ini "$BC_CONFIG_FILE"
    else
        # Minimal valid config if template missing
        echo "[Network]" > "$BC_CONFIG_FILE"
        echo "NMEA_UDPAddress=" >> "$BC_CONFIG_FILE"
        echo "NMEA_UDPPort=" >> "$BC_CONFIG_FILE"
    fi
fi

# Ensure permissions
chown -R ga:ga "$BC_CONFIG_DIR"
chown -R ga:ga "$DOCS_DIR"
chown -R ga:ga "$DESKTOP_DIR"

# 2. Clean up artifacts from potential previous runs
rm -f "$DESKTOP_DIR/capture_nmea.py"
rm -f "$DOCS_DIR/nmea_raw.log"
rm -f "$DOCS_DIR/integration_report.txt"

# 3. Kill any existing instances
pkill -f "bridgecommand" || true
pkill -f "capture_nmea.py" || true

# 4. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot
DISPLAY=:1 wmctrl -r "Bridge Command" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="