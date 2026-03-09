#!/bin/bash
echo "=== Setting up convert_reproject_gps_gpx task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Data Directories
DATA_DIR="/home/ga/GIS_Data/raw_gps"
EXPORT_DIR="/home/ga/GIS_Data/exports"

mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"

# Ensure export directory is clean
rm -f "$EXPORT_DIR/field_observations.gpkg" 2>/dev/null || true
rm -f "$EXPORT_DIR/field_observations.gpkg-journal" 2>/dev/null || true

# 2. Generate Realistic GPX Data (Waypoints + Track)
# We create a GPX file with 5 waypoints and 1 track. 
# This forces the agent to choose the correct layer type upon import.
cat > "$DATA_DIR/survey_data.gpx" << 'GPXEOF'
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="SurveyHandheld" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata>
    <name>Invasive Species Survey</name>
    <time>2023-10-15T09:00:00Z</time>
  </metadata>
  <wpt lat="37.7749" lon="-122.4194">
    <ele>10.0</ele>
    <name>Observation 001</name>
    <desc>Kudzu vine spotted</desc>
  </wpt>
  <wpt lat="37.7750" lon="-122.4180">
    <ele>12.5</ele>
    <name>Observation 002</name>
    <desc>Clearance required</desc>
  </wpt>
  <wpt lat="37.7755" lon="-122.4200">
    <ele>15.0</ele>
    <name>Observation 003</name>
    <desc>Native species present</desc>
  </wpt>
  <wpt lat="37.7760" lon="-122.4210">
    <ele>18.2</ele>
    <name>Observation 004</name>
    <desc>Soil sample taken</desc>
  </wpt>
  <wpt lat="37.7765" lon="-122.4220">
    <ele>20.1</ele>
    <name>Observation 005</name>
    <desc>Photo point A</desc>
  </wpt>
  <trk>
    <name>Survey Path</name>
    <trkseg>
      <trkpt lat="37.7749" lon="-122.4194"><ele>10.0</ele><time>2023-10-15T09:05:00Z</time></trkpt>
      <trkpt lat="37.7750" lon="-122.4180"><ele>12.5</ele><time>2023-10-15T09:10:00Z</time></trkpt>
      <trkpt lat="37.7755" lon="-122.4200"><ele>15.0</ele><time>2023-10-15T09:15:00Z</time></trkpt>
      <trkpt lat="37.7760" lon="-122.4210"><ele>18.2</ele><time>2023-10-15T09:20:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>
GPXEOF

# Set permissions
chown -R ga:ga "/home/ga/GIS_Data"

# 3. Record Initial State
date +%s > /tmp/task_start_time.txt
ls -l "$EXPORT_DIR" > /tmp/initial_export_state.txt

# 4. Launch Application
# Kill any running QGIS instances to ensure clean state
kill_qgis ga 2>/dev/null || true
sleep 1

echo "Launching QGIS..."
# Launch without a project
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to be ready
wait_for_window "QGIS" 45
sleep 3

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="