#!/bin/bash
echo "=== Setting up extract_country_boundaries task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous artifacts
echo "Cleaning previous exports..."
rm -f /home/ga/gvsig_data/exports/country_boundaries.*

# 2. Ensure the base project exists and is clean
PROJECT_SRC="/workspace/data/projects/countries_base.gvsproj"
PROJECT_DEST="/home/ga/gvsig_data/projects/countries_base.gvsproj"
mkdir -p /home/ga/gvsig_data/projects
mkdir -p /home/ga/gvsig_data/exports

if [ -f "$PROJECT_SRC" ]; then
    cp "$PROJECT_SRC" "$PROJECT_DEST"
    chown ga:ga "$PROJECT_DEST"
    chmod 644 "$PROJECT_DEST"
fi

# 3. Launch gvSIG with the project
echo "Launching gvSIG..."
launch_gvsig "$PROJECT_DEST"

# 4. Wait for window and maximize (launch_gvsig does wait, but we ensure focus)
wait_for_window "gvSIG" 60
WID=$(wmctrl -l | grep -i "gvSIG" | head -n1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="