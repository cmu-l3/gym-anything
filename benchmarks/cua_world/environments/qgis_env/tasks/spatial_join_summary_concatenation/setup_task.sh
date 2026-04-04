#!/bin/bash
echo "=== Setting up spatial_join_summary_concatenation task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
DATA_DIR="/home/ga/GIS_Data/election_data"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"

# Clean up any previous runs
rm -f "$EXPORT_DIR/precinct_inventory.geojson" 2>/dev/null || true

# Generate Synthetic Data using Python for valid GeoJSON
# Scenario: 2 Precincts (Polygons), 5 Polling Places (Points)
python3 << 'PYEOF'
import json
import os

data_dir = "/home/ga/GIS_Data/election_data"

# 1. Create Precincts (2 adjacent squares)
precincts = {
  "type": "FeatureCollection",
  "name": "precincts",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    {
      "type": "Feature",
      "properties": { "id": 1, "precinct_name": "Precinct A" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-122.5, 37.5], [-122.5, 37.6], [-122.4, 37.6], [-122.4, 37.5], [-122.5, 37.5]]]
      }
    },
    {
      "type": "Feature",
      "properties": { "id": 2, "precinct_name": "Precinct B" },
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-122.4, 37.5], [-122.4, 37.6], [-122.3, 37.6], [-122.3, 37.5], [-122.4, 37.5]]]
      }
    }
  ]
}

with open(os.path.join(data_dir, "precincts.geojson"), "w") as f:
    json.dump(precincts, f)

# 2. Create Polling Places
# Precinct A (x: -122.5 to -122.4): 2 points
# Precinct B (x: -122.4 to -122.3): 3 points
polling_places = {
  "type": "FeatureCollection",
  "name": "polling_places",
  "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
  "features": [
    # In Precinct A
    { "type": "Feature", "properties": { "id": 101, "place_name": "Lincoln Elementary" }, 
      "geometry": { "type": "Point", "coordinates": [-122.48, 37.52] } },
    { "type": "Feature", "properties": { "id": 102, "place_name": "Central Library" }, 
      "geometry": { "type": "Point", "coordinates": [-122.42, 37.58] } },
      
    # In Precinct B
    { "type": "Feature", "properties": { "id": 103, "place_name": "Westside Community Center" }, 
      "geometry": { "type": "Point", "coordinates": [-122.38, 37.52] } },
    { "type": "Feature", "properties": { "id": 104, "place_name": "Fire Station 4" }, 
      "geometry": { "type": "Point", "coordinates": [-122.35, 37.55] } },
    { "type": "Feature", "properties": { "id": 105, "place_name": "Veterans Hall" }, 
      "geometry": { "type": "Point", "coordinates": [-122.32, 37.58] } }
  ]
}

with open(os.path.join(data_dir, "polling_places.geojson"), "w") as f:
    json.dump(polling_places, f)
PYEOF

# Set permissions
chown -R ga:ga "/home/ga/GIS_Data"

# Kill any existing QGIS
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS
sleep 5
wait_for_window "QGIS" 40
sleep 2

# Maximize
WID=$(get_qgis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Record start time
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="