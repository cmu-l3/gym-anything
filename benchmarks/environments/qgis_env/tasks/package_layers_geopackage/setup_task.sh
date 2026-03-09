#!/bin/bash
set -e
echo "=== Setting up package_layers_geopackage task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/GIS_Data/exports
mkdir -p /home/ga/GIS_Data/projects
chown -R ga:ga /home/ga/GIS_Data/exports
chown -R ga:ga /home/ga/GIS_Data/projects

# Remove any pre-existing output files to prevent gaming
rm -f /home/ga/GIS_Data/exports/project_data.gpkg
rm -f /home/ga/GIS_Data/projects/delivery_project.qgs
rm -f /home/ga/GIS_Data/projects/delivery_project.qgz
rm -f /home/ga/GIS_Data/projects/delivery_project.qgz.gpkg  # common mistake file

# Verify source data files exist
for f in sample_polygon.geojson sample_points.geojson sample_lines.geojson; do
    if [ ! -f "/home/ga/GIS_Data/$f" ]; then
        echo "ERROR: Source data file missing: /home/ga/GIS_Data/$f"
        # Attempt to regenerate if missing (using the setup script logic)
        # For now, just exit as environment should be correct
        exit 1
    fi
done

# Kill any existing QGIS processes to ensure clean state
pkill -u ga -f qgis || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for QGIS window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "QGIS" > /dev/null; then
        echo "QGIS window found"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "QGIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="