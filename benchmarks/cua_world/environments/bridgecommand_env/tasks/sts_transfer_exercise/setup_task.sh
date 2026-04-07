#!/bin/bash
echo "=== Setting up STS Transfer Exercise Task ==="

BC_DATA="/opt/bridgecommand"
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
BC_USER_DATA="/home/ga/.Bridge Command/5.10"
SCENARIO_DIR="$BC_DATA/Scenarios/n) Solent STS Transfer Exercise"

# 1. Clean up any previous attempts
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "/home/ga/Documents/sts_operation_briefing.txt" 2>/dev/null || true

# 2. Reset bc5.ini to defaults to ensure a clean starting state
# (We want the agent to explicitly set the required radar settings)
mkdir -p "$BC_CONFIG_DIR"
mkdir -p "$BC_USER_DATA"

# Default content with standard long-range radar settings
cat > /tmp/default_bc5.ini << EOF
[Graphics]
view_angle=60
width=1024
height=768
windowed=1

[RADAR]
max_radar_range=48
radar_range_resolution=128
full_radar=0
arpa_on=0
EOF

cp /tmp/default_bc5.ini "$BC_CONFIG_DIR/bc5.ini"
cp /tmp/default_bc5.ini "$BC_DATA/bc5.ini" 2>/dev/null || true
chown -R ga:ga "$BC_CONFIG_DIR"
chown -R ga:ga "/home/ga/.config"

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Ensure Bridge Command is ready
if [ ! -x "$BC_DATA/bridgecommand" ]; then
    echo "ERROR: Bridge Command binary not found"
    # Try to fix symlink if needed
    if [ -x "/usr/local/bin/bridgecommand" ]; then
        ln -sf "/usr/local/bin/bridgecommand" "$BC_DATA/bridgecommand"
    fi
fi

# 5. Launch Bridge Command briefly to ensure it works, then kill it
# This ensures any first-run setup logic completes
echo "Warming up Bridge Command..."
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_warmup.log 2>&1 &"
sleep 5
pkill -f "bridgecommand" 2>/dev/null || true

# 6. Capture initial state screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task Setup Complete ==="