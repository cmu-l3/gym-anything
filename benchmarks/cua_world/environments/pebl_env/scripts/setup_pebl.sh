#!/bin/bash
set -e

echo "=== Setting up PEBL environment ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Wait for desktop to be ready
echo "Waiting for desktop..."
sleep 5
for i in $(seq 1 30); do
    if DISPLAY=:1 xdotool getactivewindow &>/dev/null; then
        echo "Desktop is ready"
        break
    fi
    sleep 2
done

# Find PEBL binary and battery paths
PEBL_BIN=""
if [ -f /usr/local/bin/pebl2 ]; then
    PEBL_BIN="/usr/local/bin/pebl2"
elif [ -f /opt/pebl/bin/pebl2 ]; then
    PEBL_BIN="/opt/pebl/bin/pebl2"
elif [ -f /usr/local/bin/pebl ]; then
    PEBL_BIN="/usr/local/bin/pebl"
elif [ -f /opt/pebl/bin/pebl ]; then
    PEBL_BIN="/opt/pebl/bin/pebl"
fi

BATTERY_DIR=""
if [ -d /home/ga/pebl/battery ]; then
    BATTERY_DIR="/home/ga/pebl/battery"
elif [ -d /usr/local/share/pebl2/battery ]; then
    BATTERY_DIR="/usr/local/share/pebl2/battery"
elif [ -d /usr/local/pebl2/battery ]; then
    BATTERY_DIR="/usr/local/pebl2/battery"
elif [ -d /opt/pebl/battery ]; then
    BATTERY_DIR="/opt/pebl/battery"
fi

echo "PEBL binary: $PEBL_BIN"
echo "Battery directory: $BATTERY_DIR"

# Create working directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/experiments
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/pebl
chown -R ga:ga /home/ga/Documents

# Create desktop shortcut for PEBL launcher
cat > /home/ga/Desktop/PEBL_Launcher.desktop << 'EOF'
[Desktop Entry]
Name=PEBL Launcher
Comment=Psychology Experiment Building Language
Exec=/usr/local/bin/run-pebl --launcher
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Education;Science;
EOF
chmod +x /home/ga/Desktop/PEBL_Launcher.desktop
chown ga:ga /home/ga/Desktop/PEBL_Launcher.desktop

# Store paths for task scripts to use
cat > /home/ga/pebl/.pebl_config << EOF
PEBL_BIN=$PEBL_BIN
BATTERY_DIR=$BATTERY_DIR
EOF
chown ga:ga /home/ga/pebl/.pebl_config

# List available tests in battery for reference
if [ -n "$BATTERY_DIR" ] && [ -d "$BATTERY_DIR" ]; then
    echo "=== Available PEBL Test Battery experiments ==="
    find "$BATTERY_DIR" -name "*.pbl" -type f | head -30
    echo "..."
fi

echo "=== PEBL setup complete ==="
