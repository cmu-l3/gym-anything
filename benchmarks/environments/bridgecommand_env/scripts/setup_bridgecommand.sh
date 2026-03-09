#!/bin/bash
set -e

echo "=== Setting up Bridge Command ==="

# Wait for desktop to be ready
sleep 5

# Bridge Command is installed to /opt/bridgecommand (built from source)
BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"

if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found at $BC_BIN"
    exit 1
fi

echo "Bridge Command binary: $BC_BIN"
echo "$BC_BIN" > /tmp/bc_bin_path.txt
echo "$BC_DATA" > /tmp/bc_data_dir.txt

# Create Bridge Command config directory for the ga user
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
mkdir -p "$BC_CONFIG_DIR"

# Copy pre-configured bc5.ini for windowed mode (critical for VM usage)
if [ -f /workspace/config/bc5.ini ]; then
    cp /workspace/config/bc5.ini "$BC_CONFIG_DIR/bc5.ini"
    echo "Copied pre-configured bc5.ini to user config"
fi

# Also copy bc5.ini to the program data directory (BC reads both locations)
cp /workspace/config/bc5.ini "$BC_DATA/bc5.ini" 2>/dev/null || true

# Set ownership
chown -R ga:ga "$BC_CONFIG_DIR"
chown -R ga:ga /home/ga/.config

# Copy custom scenario data if available
if [ -d "$BC_DATA/Scenarios" ] && [ -d /workspace/data/portsmouth_approach ]; then
    echo "Installing custom scenario: Portsmouth Approach..."
    cp -r /workspace/data/portsmouth_approach "$BC_DATA/Scenarios/m) Portsmouth Approach Custom"
    echo "Custom scenario installed"
fi

# List available scenarios
echo "=== Available Scenarios ==="
ls "$BC_DATA/Scenarios/" 2>/dev/null || echo "No scenarios found"

# Create launcher script that cds to the data directory before launching
# Bridge Command must run from its data directory to find Models/, World/, Scenarios/
cat > /home/ga/Desktop/launch_bridgecommand.sh << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=:1
cd /opt/bridgecommand
./bridgecommand "$@" &
LAUNCHEOF
chmod +x /home/ga/Desktop/launch_bridgecommand.sh
chown ga:ga /home/ga/Desktop/launch_bridgecommand.sh

# Create desktop entry
cat > /home/ga/Desktop/BridgeCommand.desktop << 'EOF'
[Desktop Entry]
Name=Bridge Command
Comment=Ship Bridge Simulator
Exec=bash -c "cd /opt/bridgecommand && ./bridgecommand"
Icon=applications-games
Terminal=false
Type=Application
Categories=Education;Simulation;
EOF
chmod +x /home/ga/Desktop/BridgeCommand.desktop
chown ga:ga /home/ga/Desktop/BridgeCommand.desktop

# Warm-up launch: start BridgeCommand to initialize first-run state, then close
# Must cd to /opt/bridgecommand for BC to find its data files
echo "Performing warm-up launch of Bridge Command..."
su - ga -c "cd /opt/bridgecommand && DISPLAY=:1 ./bridgecommand > /tmp/bc_warmup.log 2>&1 &"
sleep 8

# Check if Bridge Command is running
BC_PID=$(pgrep -f "/opt/bridgecommand/bridgecommand" 2>/dev/null | head -1)
if [ -n "$BC_PID" ]; then
    echo "Bridge Command started successfully for warm-up (PID $BC_PID)"
    # Take a diagnostic screenshot
    su - ga -c "DISPLAY=:1 scrot /tmp/bc_warmup_screenshot.png" 2>/dev/null || true
    # Kill the warm-up instance
    kill "$BC_PID" 2>/dev/null || pkill -f "bridgecommand" 2>/dev/null || true
    sleep 2
    echo "Warm-up launch complete, Bridge Command closed"
else
    echo "WARNING: Bridge Command may not have started during warm-up"
    cat /tmp/bc_warmup.log 2>/dev/null || true
fi

echo "=== Bridge Command setup complete ==="
echo "Binary: $BC_BIN"
echo "Data: $BC_DATA"
echo "Config: $BC_CONFIG_DIR"
