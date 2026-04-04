#!/bin/bash
echo "=== Setting up generate_random_survey_points task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure exports directory exists and is clean
EXPORTS_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORTS_DIR"
rm -f "$EXPORTS_DIR/madagascar_survey."* 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR"

# Verify input data exists
check_countries_shapefile || exit 1

# Kill any running gvSIG instances
kill_gvsig

# Use pre-built project to ensure consistent starting state
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

# Restore clean project file
if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
    echo "Restored clean project: $PREBUILT_PROJECT"
fi

# Launch gvSIG
echo "Launching gvSIG with project..."
if [ -f "$PREBUILT_PROJECT" ]; then
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "WARNING: Prebuilt project not found, launching empty."
    launch_gvsig ""
fi

# Maximize window (extra check)
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "gvSIG" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="