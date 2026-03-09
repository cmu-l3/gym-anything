#!/bin/bash
set -e

echo "=== Setting up CSV Import and Voronoi Analysis task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create required directories with correct permissions
mkdir -p /home/ga/GIS_Data/exports
mkdir -p /home/ga/GIS_Data/projects
chown -R ga:ga /home/ga/GIS_Data

# Remove previous task artifacts to ensure clean state
rm -f /home/ga/GIS_Data/exports/voronoi_zones.*
rm -f /home/ga/GIS_Data/exports/Voronoi*
rm -f /home/ga/GIS_Data/exports/thiessen*
rm -f /home/ga/GIS_Data/bay_area_water_stations.csv

# Create CSV data file with water quality monitoring stations
# Based on real USGS NWIS monitoring station locations in SF Bay Area
echo "Creating input CSV file..."
cat > /home/ga/GIS_Data/bay_area_water_stations.csv << 'CSVEOF'
station_id,station_name,longitude,latitude,ph,dissolved_oxygen_mg_l,temperature_c
USGS-11169025,Alviso Slough,-121.972,37.431,7.8,6.2,18.5
USGS-11162765,Guadalupe River,-121.929,37.352,7.5,7.1,17.2
USGS-374811122235,San Leandro Bay,-122.393,37.803,8.1,5.8,16.8
USGS-11180700,San Lorenzo Creek,-122.119,37.667,7.6,8.3,15.4
USGS-372806122032,Coyote Creek,-122.057,37.468,7.9,6.7,17.8
USGS-11169500,Alameda Creek,-121.950,37.596,7.3,7.8,16.1
USGS-374342122101,Oakland Harbor,-122.170,37.728,8.0,5.5,17.0
USGS-11160000,Niles Canyon,-121.960,37.575,7.7,6.9,16.5
CSVEOF

# Set ownership
chown ga:ga /home/ga/GIS_Data/bay_area_water_stations.csv

# Kill any existing QGIS instance
kill_qgis ga 2>/dev/null || true
sleep 2

# Launch QGIS with clean state
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis --noversioncheck --skipbadlayers > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS window to appear
wait_for_window "QGIS" 45

# Give QGIS time to fully initialize
sleep 5

# Maximize and focus QGIS window
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Input CSV: /home/ga/GIS_Data/bay_area_water_stations.csv"