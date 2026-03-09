#!/bin/bash
echo "=== Setting up Unique Values Symbology Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ensure directories exist
mkdir -p /home/ga/gvsig_data/projects
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Remove previous outputs to ensure fresh creation
rm -f "/home/ga/gvsig_data/projects/continent_categories.gvsproj"
rm -f "/home/ga/gvsig_data/exports/continent_map.png"

# Verify input data exists
check_countries_shapefile || exit 1

# Kill any existing gvSIG instances
kill_gvsig

# Launch gvSIG with a fresh state (no project loaded)
echo "Launching gvSIG Desktop..."
launch_gvsig ""

# Wait for window and maximize
if wait_for_window "gvSIG" 60; then
    echo "gvSIG window detected."
    # Maximize window
    DISPLAY=:1 wmctrl -r "gvSIG" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus
    DISPLAY=:1 wmctrl -a "gvSIG" 2>/dev/null || true
else
    echo "WARNING: gvSIG window not detected, but continuing setup."
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png
echo "Initial state captured."

echo "=== Setup complete ==="