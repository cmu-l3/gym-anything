#!/bin/bash
echo "=== Setting up optimize_patrol_route task ==="

# Define paths (using C:/ format for Windows compatibility within Git Bash/MSYS environments)
WORKSPACE_DIR="C:/workspace"
DATA_DIR="$WORKSPACE_DIR/data"
OUTPUT_FILE="$WORKSPACE_DIR/optimized_patrol.gpx"

mkdir -p "$DATA_DIR"
mkdir -p C:/tmp

# Record task start time (for anti-gaming timestamp checks)
date +%s > C:/tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f "$OUTPUT_FILE" 2>/dev/null

# Generate the initial camera_stations.gpx data with an intentionally inefficient order (criss-crossing path)
cat << 'EOF' > "$DATA_DIR/camera_stations.gpx"
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Garmin BaseCamp">
  <wpt lat="42.4490" lon="-71.1040"><name>Station 1 - Sheepfold</name></wpt>
  <wpt lat="42.4340" lon="-71.1060"><name>Station 2 - Bellevue</name></wpt>
  <wpt lat="42.4460" lon="-71.0950"><name>Station 3 - Spot Pond</name></wpt>
  <wpt lat="42.4360" lon="-71.1120"><name>Station 4 - Panther Cave</name></wpt>
  <wpt lat="42.4420" lon="-71.1000"><name>Station 5 - Cross Fells</name></wpt>
</gpx>
EOF

echo "Created inefficient waypoint dataset at: $DATA_DIR/camera_stations.gpx"

# Launch Garmin BaseCamp using powershell if it isn't already running
echo "Ensuring Garmin BaseCamp is running..."
powershell.exe -Command "if (-not (Get-Process BaseCamp -ErrorAction SilentlyContinue)) { Start-Process 'C:\Program Files (x86)\Garmin\BaseCamp\BaseCamp.exe' }"

# Wait for application to stabilize
sleep 10

# Take initial state screenshot (if scrot/import is available in the shell environment)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="