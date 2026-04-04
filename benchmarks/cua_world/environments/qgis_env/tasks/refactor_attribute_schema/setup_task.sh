#!/bin/bash
echo "=== Setting up refactor_attribute_schema task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# Directories
DATA_DIR="/home/ga/GIS_Data/raw"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "/home/ga/GIS_Data"

# Clean previous output
rm -f "$EXPORT_DIR/clean_stations.geojson"

# Generate Source Data (Shapefile with messy attributes)
# We generate GeoJSON first, then convert to Shapefile to ensure specific field types (like String for numbers)
echo "Generating legacy data..."
cat > "$DATA_DIR/temp_legacy.geojson" << 'EOF'
{
"type": "FeatureCollection",
"name": "legacy_stations",
"crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
"features": [
{ "type": "Feature", "properties": { "STN_ID_X": "STN001", "LOC_NM": "North Point", "READ_VAL": "12.5", "OBS_DT": "2023-01-01", "LEGACY_CD": "X99", "TECH_N": "Routine check" }, "geometry": { "type": "Point", "coordinates": [ -0.12, 51.50 ] } },
{ "type": "Feature", "properties": { "STN_ID_X": "STN002", "LOC_NM": "South Quay", "READ_VAL": "13.2", "OBS_DT": "2023-01-02", "LEGACY_CD": "X99", "TECH_N": "Bat changed" }, "geometry": { "type": "Point", "coordinates": [ -0.11, 51.49 ] } },
{ "type": "Feature", "properties": { "STN_ID_X": "STN003", "LOC_NM": "East End", "READ_VAL": "11.8", "OBS_DT": "2023-01-03", "LEGACY_CD": "Y01", "TECH_N": "OK" }, "geometry": { "type": "Point", "coordinates": [ -0.09, 51.51 ] } },
{ "type": "Feature", "properties": { "STN_ID_X": "STN004", "LOC_NM": "West Side", "READ_VAL": "12.0", "OBS_DT": "2023-01-04", "LEGACY_CD": "Y01", "TECH_N": "Sensor drift" }, "geometry": { "type": "Point", "coordinates": [ -0.13, 51.50 ] } },
{ "type": "Feature", "properties": { "STN_ID_X": "STN005", "LOC_NM": "City Ctr", "READ_VAL": "14.1", "OBS_DT": "2023-01-05", "LEGACY_CD": "Z22", "TECH_N": "Calibrated" }, "geometry": { "type": "Point", "coordinates": [ -0.10, 51.51 ] } },
{ "type": "Feature", "properties": { "STN_ID_X": "STN006", "LOC_NM": "Docklands", "READ_VAL": "10.9", "OBS_DT": "2023-01-06", "LEGACY_CD": "Z22", "TECH_N": "No access" }, "geometry": { "type": "Point", "coordinates": [ -0.08, 51.50 ] } },
{ "type": "Feature", "properties": { "STN_ID_X": "STN007", "LOC_NM": "Park Hill", "READ_VAL": "11.5", "OBS_DT": "2023-01-07", "LEGACY_CD": "X99", "TECH_N": "OK" }, "geometry": { "type": "Point", "coordinates": [ -0.12, 51.52 ] } },
{ "type": "Feature", "properties": { "STN_ID_X": "STN008", "LOC_NM": "River Bank", "READ_VAL": "13.0", "OBS_DT": "2023-01-08", "LEGACY_CD": "X99", "TECH_N": "Flooded" }, "geometry": { "type": "Point", "coordinates": [ -0.11, 51.48 ] } },
{ "type": "Feature", "properties": { "STN_ID_X": "STN009", "LOC_NM": "Hill Top", "READ_VAL": "9.8", "OBS_DT": "2023-01-09", "LEGACY_CD": "Y01", "TECH_N": "Windy" }, "geometry": { "type": "Point", "coordinates": [ -0.14, 51.53 ] } },
{ "type": "Feature", "properties": { "STN_ID_X": "STN010", "LOC_NM": "Valley", "READ_VAL": "12.2", "OBS_DT": "2023-01-10", "LEGACY_CD": "Z22", "TECH_N": "OK" }, "geometry": { "type": "Point", "coordinates": [ -0.10, 51.49 ] } }
]
}
EOF

# Convert to Shapefile using ogr2ogr (ensuring READ_VAL stays string)
# -lco encoding=UTF-8 ensures text encoding
rm -f "$DATA_DIR/legacy_stations.shp" "$DATA_DIR/legacy_stations.shx" "$DATA_DIR/legacy_stations.dbf" "$DATA_DIR/legacy_stations.prj"
ogr2ogr -f "ESRI Shapefile" "$DATA_DIR/legacy_stations.shp" "$DATA_DIR/temp_legacy.geojson" \
    -lco ENCODING=UTF-8

# Verify the creation
if [ ! -f "$DATA_DIR/legacy_stations.shp" ]; then
    echo "ERROR: Failed to create shapefile"
    exit 1
fi

rm "$DATA_DIR/temp_legacy.geojson"
chown ga:ga "$DATA_DIR/legacy_stations."*

# Record start time
date +%s > /tmp/task_start_timestamp

# Kill QGIS
kill_qgis ga 2>/dev/null || true

# Launch QGIS with the layer loaded
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis '$DATA_DIR/legacy_stations.shp' > /tmp/qgis_task.log 2>&1 &"

sleep 10
wait_for_window "QGIS" 40
sleep 2

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="