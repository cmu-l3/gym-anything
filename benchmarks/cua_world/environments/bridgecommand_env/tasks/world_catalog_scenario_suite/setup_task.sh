#!/bin/bash
set -e
echo "=== Setting up World Catalog & Scenario Suite Task ==="

# Define paths
SCENARIO_ROOT="/opt/bridgecommand/Scenarios"
DOCS_DIR="/home/ga/Documents"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_SYSTEM="/opt/bridgecommand/bc5.ini"

# 1. Clean up any previous attempts (Anti-Gaming: Ensure fresh start)
echo "Cleaning previous artifacts..."
rm -rf "$SCENARIO_ROOT/x1) Open Water Exercise"
rm -rf "$SCENARIO_ROOT/x2) Coastal Pilotage Exercise"
rm -rf "$SCENARIO_ROOT/x3) Restricted Visibility Exercise"
rm -f "$DOCS_DIR/world_catalog.txt"
rm -f "$DOCS_DIR/curriculum_mapping.txt"

# 2. Reset bc5.ini to defaults (disable radar features to force agent to set them)
echo "Resetting configuration..."
mkdir -p "$(dirname "$BC_CONFIG_USER")"
# Create a default config with radar features disabled
cat > "$BC_CONFIG_USER" << EOF
view_angle=90
joystick_sensitivity=1.0
mouse_sensitivity=1.0
arpa_on=0
full_radar=0
radar_range_resolution=64
max_radar_range=24
EOF
chown -R ga:ga "/home/ga/.config"

# Also reset system config if possible/writable, or ignore if not
if [ -w "$BC_CONFIG_SYSTEM" ]; then
    cp "$BC_CONFIG_USER" "$BC_CONFIG_SYSTEM"
fi

# 3. Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 4. Record initial state (List of worlds for verification reference)
echo "Recording available worlds..."
ls -1 /opt/bridgecommand/World/ > /tmp/available_worlds_list.txt

# 5. Record start timestamp
date +%s > /tmp/task_start_time.txt

# 6. Setup complete screenshot
# Just show the desktop with file manager open to /opt/bridgecommand/World/ to give a hint?
# Or just empty desktop. Let's open the file manager to the root BC dir to be helpful.
if ! pgrep -f "nautilus" > /dev/null; then
    su - ga -c "DISPLAY=:1 nautilus /opt/bridgecommand/World &"
    sleep 3
fi

DISPLAY=:1 wmctrl -r "World" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="