#!/bin/bash
echo "=== Setting up variable_distance_buffer_zones task ==="

source /workspace/scripts/task_utils.sh

# Ensure GIS data directory exists
mkdir -p /home/ga/GIS_Data
mkdir -p /home/ga/GIS_Data/exports

# Generate the input GeoJSON file with Python
# We use simple geometries in UTM Zone 10N (EPSG:32610) to ensure metric units work natively
echo "Generating input data..."
python3 << 'PYEOF'
import json
import os

# Define 3 road features with different impact distances
# Using coordinates roughly in San Francisco/Bay Area but projected to UTM 10N
# Coordinates are arbitrary valid UTM 10N coordinates
features = [
    {
        "type": "Feature",
        "properties": {"id": 1, "type": "Highway", "impact_dist": 150},
        "geometry": {
            "type": "LineString",
            "coordinates": [[550000, 4180000], [550000, 4181000]] # Vertical line 1km long
        }
    },
    {
        "type": "Feature",
        "properties": {"id": 2, "type": "Arterial", "impact_dist": 80},
        "geometry": {
            "type": "LineString",
            "coordinates": [[552000, 4180000], [552000, 4181000]] # Vertical line 1km long
        }
    },
    {
        "type": "Feature",
        "properties": {"id": 3, "type": "Local", "impact_dist": 30},
        "geometry": {
            "type": "LineString",
            "coordinates": [[554000, 4180000], [554000, 4181000]] # Vertical line 1km long
        }
    }
]

geojson = {
    "type": "FeatureCollection",
    "name": "roads_noise_attributed",
    "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:EPSG::32610" } },
    "features": features
}

output_path = "/home/ga/GIS_Data/roads_noise_attributed.geojson"
with open(output_path, 'w') as f:
    json.dump(geojson, f, indent=2)

print(f"Created {output_path} with {len(features)} features")
PYEOF

# Set permissions
chown -R ga:ga /home/ga/GIS_Data

# Clean up previous exports
rm -f /home/ga/GIS_Data/exports/variable_buffers.geojson 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Kill any existing QGIS
kill_qgis ga 2>/dev/null || true

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS to start
wait_for_window "QGIS" 45

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="