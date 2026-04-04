#!/bin/bash
echo "=== Setting up nearest_neighbor_distance_matrix task ==="

source /workspace/scripts/task_utils.sh

# Definitions
DATA_DIR="/home/ga/GIS_Data"
EXPORT_DIR="$DATA_DIR/exports"
PROJECT_DIR="$DATA_DIR/projects"
INPUT_FILE="$DATA_DIR/us_western_capitals.geojson"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$EXPORT_DIR" "$PROJECT_DIR"
chown -R ga:ga "$DATA_DIR"

# Create Input Data: US Western Capitals GeoJSON
# Source: Real approximate coordinates
cat > "$INPUT_FILE" << 'EOF'
{
  "type": "FeatureCollection",
  "name": "us_western_capitals",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    { "type": "Feature", "properties": { "name": "Sacramento", "state": "CA", "population": 524943 }, "geometry": { "type": "Point", "coordinates": [-121.4944, 38.5816] } },
    { "type": "Feature", "properties": { "name": "Carson City", "state": "NV", "population": 58639 }, "geometry": { "type": "Point", "coordinates": [-119.7674, 39.1638] } },
    { "type": "Feature", "properties": { "name": "Salem", "state": "OR", "population": 175535 }, "geometry": { "type": "Point", "coordinates": [-123.0351, 44.9429] } },
    { "type": "Feature", "properties": { "name": "Olympia", "state": "WA", "population": 55605 }, "geometry": { "type": "Point", "coordinates": [-122.9007, 47.0379] } },
    { "type": "Feature", "properties": { "name": "Boise", "state": "ID", "population": 235684 }, "geometry": { "type": "Point", "coordinates": [-116.2023, 43.6150] } },
    { "type": "Feature", "properties": { "name": "Helena", "state": "MT", "population": 32091 }, "geometry": { "type": "Point", "coordinates": [-112.0270, 46.5891] } },
    { "type": "Feature", "properties": { "name": "Cheyenne", "state": "WY", "population": 65132 }, "geometry": { "type": "Point", "coordinates": [-104.8202, 41.1400] } },
    { "type": "Feature", "properties": { "name": "Salt Lake City", "state": "UT", "population": 199723 }, "geometry": { "type": "Point", "coordinates": [-111.8910, 40.7608] } },
    { "type": "Feature", "properties": { "name": "Denver", "state": "CO", "population": 715522 }, "geometry": { "type": "Point", "coordinates": [-104.9903, 39.7392] } },
    { "type": "Feature", "properties": { "name": "Phoenix", "state": "AZ", "population": 1608139 }, "geometry": { "type": "Point", "coordinates": [-112.0740, 33.4484] } },
    { "type": "Feature", "properties": { "name": "Santa Fe", "state": "NM", "population": 87505 }, "geometry": { "type": "Point", "coordinates": [-105.9378, 35.6870] } },
    { "type": "Feature", "properties": { "name": "Bismarck", "state": "ND", "population": 73622 }, "geometry": { "type": "Point", "coordinates": [-100.7837, 46.8083] } },
    { "type": "Feature", "properties": { "name": "Pierre", "state": "SD", "population": 14091 }, "geometry": { "type": "Point", "coordinates": [-100.3510, 44.3683] } },
    { "type": "Feature", "properties": { "name": "Lincoln", "state": "NE", "population": 291082 }, "geometry": { "type": "Point", "coordinates": [-96.7005, 40.8136] } },
    { "type": "Feature", "properties": { "name": "Topeka", "state": "KS", "population": 126587 }, "geometry": { "type": "Point", "coordinates": [-95.6752, 39.0473] } },
    { "type": "Feature", "properties": { "name": "Oklahoma City", "state": "OK", "population": 681054 }, "geometry": { "type": "Point", "coordinates": [-97.5164, 35.4676] } },
    { "type": "Feature", "properties": { "name": "Austin", "state": "TX", "population": 961855 }, "geometry": { "type": "Point", "coordinates": [-97.7431, 30.2672] } }
  ]
}
EOF

# Set permissions
chown ga:ga "$INPUT_FILE"

# Clean previous results
rm -f "$EXPORT_DIR/capital_distance_matrix.csv" 2>/dev/null || true
rm -f "$PROJECT_DIR/distance_analysis.qgz" 2>/dev/null || true
rm -f "$PROJECT_DIR/distance_analysis.qgs" 2>/dev/null || true

# Record initial timestamp for file creation checks
date +%s > /tmp/task_start_timestamp

# Ensure QGIS is fresh
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for window
wait_for_window "QGIS" 40
sleep 3

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Created $INPUT_FILE with 17 features."