#!/bin/bash
echo "=== Setting up Emergency Anchorage Exercise ==="

# Define paths
BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/n) Cowes Roads Emergency Anchorage"
DOC_DIR="/home/ga/Documents"
DOC_FILE="$DOC_DIR/anchorage_approach_plan.txt"

# 1. Clean previous attempts
echo "Cleaning previous scenario and documents..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$DOC_FILE" 2>/dev/null || true
mkdir -p "$DOC_DIR"
chown ga:ga "$DOC_DIR"

# 2. Reset Configuration (bc5.ini) to defaults to ensure agent actually changes them
# Reset to a 'clean' state where radar settings are generic/wrong for this task
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="$BC_DATA/bc5.ini"

mkdir -p "$(dirname "$BC_CONFIG_USER")"

# Create default clean config
cat > /tmp/bc5_clean.ini << EOF
[Graphics]
view_angle=90
[RADAR]
arpa_on=0
full_radar=0
radar_range_resolution=64
max_radar_range=48
[Startup]
hide_instruments=0
EOF

cp /tmp/bc5_clean.ini "$BC_CONFIG_USER"
cp /tmp/bc5_clean.ini "$BC_CONFIG_DATA" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config"

# 3. Record Task Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 4. Ensure Bridge Command is operational
if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found at $BC_BIN"
    # Attempt to locate it
    BC_BIN=$(which bridgecommand 2>/dev/null)
    if [ -z "$BC_BIN" ]; then
        echo "CRITICAL: Bridge Command not installed."
        exit 1
    fi
fi

# 5. Launch Bridge Command for the agent to start
# We launch it so the agent sees the launcher immediately
echo "Launching Bridge Command..."
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_setup.log 2>&1 &"

# Wait for window
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Bridge Command window detected."
        break
    fi
    sleep 1
done

# Focus window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true
sleep 1

# 6. Capture Initial State Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="