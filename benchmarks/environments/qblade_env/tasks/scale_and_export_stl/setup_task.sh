#!/bin/bash
echo "=== Setting up scale_and_export_stl task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directories exist and clean up previous artifacts
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects
rm -f "/home/ga/Documents/nrel_5mw_model_1m.stl" 2>/dev/null || true
rm -f "/home/ga/Documents/projects/nrel_5mw_scaled.wpa" 2>/dev/null || true

# Find the NREL 5MW sample project
# Check standard locations
SAMPLE_PROJECT=""
POSSIBLE_LOCATIONS=(
    "/home/ga/Documents/sample_projects/NREL_5MW_Reference_Blade.wpa"
    "/home/ga/Documents/sample_projects/NREL_5MW_Reference.wpa"
    "/home/ga/Documents/sample_projects/NREL 5MW Reference Blade.wpa"
)

# Also check the QBlade install dir if not found in Documents
QBLADE_SAMPLE_DIR=$(find /opt/qblade -type d -name "sample projects" 2>/dev/null | head -1)
if [ -n "$QBLADE_SAMPLE_DIR" ]; then
    POSSIBLE_LOCATIONS+=("$QBLADE_SAMPLE_DIR/NREL_5MW_Reference_Blade.wpa")
fi

for loc in "${POSSIBLE_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        SAMPLE_PROJECT="$loc"
        echo "Found sample project at: $loc"
        break
    fi
done

# Launch QBlade
echo "Launching QBlade..."
# If we found the project, try to launch with it. Otherwise just launch empty.
if [ -n "$SAMPLE_PROJECT" ]; then
    launch_qblade "$SAMPLE_PROJECT"
else
    echo "WARNING: NREL 5MW sample project not found automatically. Agent will need to browse."
    launch_qblade
fi

# Wait for QBlade window
wait_for_qblade 60

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="