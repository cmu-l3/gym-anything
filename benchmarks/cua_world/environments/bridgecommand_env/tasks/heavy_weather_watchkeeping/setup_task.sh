#!/bin/bash
echo "=== Setting up heavy_weather_watchkeeping task ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/n) English Channel Heavy Weather Exercise"
DOCS_DIR="/home/ga/Documents"
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"

# 1. Clean up previous run artifacts
# Remove the target scenario directory if it exists
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# Remove documents
rm -f "$DOCS_DIR/met_briefing_heavy_weather.txt"
rm -f "$DOCS_DIR/masters_standing_orders.txt"
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 2. Reset Configuration to a known baseline
# We want to detect changes to bc5.ini, so we start with defaults
echo "Resetting Bridge Command configuration..."
mkdir -p "$BC_CONFIG_DIR"

# Create a default bc5.ini with standard values (different from target)
cat > "$BC_CONFIG_DIR/bc5.ini" << EOF
view_angle=90
radar_range_resolution=128
max_radar_range=24
arpa_on=0
full_radar=0
EOF
chown -R ga:ga "$BC_CONFIG_DIR"

# Also reset the installation directory config which BC sometimes reads
cp "$BC_CONFIG_DIR/bc5.ini" "$BC_DATA/bc5.ini" 2>/dev/null || true

# 3. Record Task Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch Bridge Command
# The agent needs the application open to access the Settings editor if they choose,
# or to verify their scenario.
echo "Starting Bridge Command..."
pkill -f "bridgecommand" 2>/dev/null || true
sleep 2

# BC must be run from its directory
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_task.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Bridge Command window detected."
        break
    fi
    sleep 1
done

# Focus window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="