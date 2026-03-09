#!/bin/bash
set -e
echo "=== Exporting multi-ring buffer results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/task_result.json"
OUTPUT_PATH="/home/ga/GIS_Data/exports/evacuation_zones.geojson"
ALT_OUTPUT_PATH="/home/ga/GIS_Data/exports/evacuation_zones.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check for output file (handle alternative extensions)
FOUND_PATH=""
if [ -f "$OUTPUT_PATH" ]; then
    FOUND_PATH="$OUTPUT_PATH"
elif [ -f "$ALT_OUTPUT_PATH" ]; then
    FOUND_PATH="$ALT_OUTPUT_PATH"
else
    # Search for any recently created geojson in exports
    FOUND_PATH=$(find /home/ga/GIS_Data/exports/ -name "*.geojson" -o -name "*.json" -mmin -10 2>/dev/null | head -1)
fi

# Check if QGIS is still running
APP_RUNNING=$(pgrep -f "qgis" > /dev/null && echo "true" || echo "false")

# Use Python to analyze the output file safely
python3 << PYEOF
import json
import os
import sys
import time

result = {
    "file_exists": False,
    "file_path": "",
    "file_size_bytes": 0,
    "is_valid_geojson": False,
    "feature_count": 0,
    "geometry_types": [],
    "polygon_feature_count": 0,
    "has_distance_attribute": False,
    "distance_attribute_name": "",
    "unique_distance_values": [],
    "file_created_during_task": False,
    "task_start_time": int("$TASK_START"),
    "app_was_running": "$APP_RUNNING" == "true",
    "screenshot_path": "/tmp/task_final.png"
}

found_path = "$FOUND_PATH"

if found_path and os.path.isfile(found_path):
    result["file_exists"] = True
    result["file_path"] = found_path
    result["file_size_bytes"] = os.path.getsize(found_path)
    
    # Check modification time
    mtime = int(os.path.getmtime(found_path))
    if mtime > result["task_start_time"]:
        result["file_created_during_task"] = True

    # Parse GeoJSON content
    try:
        with open(found_path, 'r') as f:
            data = json.load(f)
        
        if data.get("type") == "FeatureCollection" and "features" in data:
            result["is_valid_geojson"] = True
            features = data["features"]
            result["feature_count"] = len(features)
            
            geom_types = set()
            poly_count = 0
            distance_attr = None
            distance_values = set()
            
            # Keywords to look for in attributes
            dist_keywords = ["dist", "ring", "buffer", "zone"]
            
            for feat in features:
                # Check geometry
                geom = feat.get("geometry", {})
                gtype = geom.get("type", "Unknown")
                geom_types.add(gtype)
                if gtype in ["Polygon", "MultiPolygon"]:
                    poly_count += 1
                
                # Check properties for distance info
                props = feat.get("properties", {})
                for key, val in props.items():
                    if any(k in key.lower() for k in dist_keywords):
                        # Found a potential distance attribute
                        if distance_attr is None:
                            distance_attr = key
                        if val is not None:
                            distance_values.add(str(val))
            
            result["geometry_types"] = list(geom_types)
            result["polygon_feature_count"] = poly_count
            result["has_distance_attribute"] = distance_attr is not None
            if distance_attr:
                result["distance_attribute_name"] = distance_attr
                result["unique_distance_values"] = list(distance_values)
                
    except Exception as e:
        result["error"] = str(e)

# Write result to JSON file
with open("$RESULT_FILE", 'w') as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# Ensure result file has correct permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="