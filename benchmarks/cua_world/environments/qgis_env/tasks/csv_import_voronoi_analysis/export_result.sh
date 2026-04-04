#!/bin/bash
set -e

echo "=== Exporting Voronoi task results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/task_result.json"
OUTPUT_PATH="/home/ga/GIS_Data/exports/voronoi_zones.geojson"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Search for output file at expected and alternative locations
ALT_PATHS=(
    "/home/ga/GIS_Data/exports/voronoi*.geojson"
    "/home/ga/GIS_Data/exports/Voronoi*.geojson"
    "/home/ga/GIS_Data/exports/thiessen*.geojson"
    "/home/ga/GIS_Data/exports/Thiessen*.geojson"
    "/home/ga/GIS_Data/voronoi_zones.geojson"
    "/home/ga/GIS_Data/voronoi*.geojson"
    "/home/ga/Desktop/voronoi*.geojson"
    "/tmp/voronoi*.geojson"
    "/tmp/processing_*/*.geojson"
)

FOUND_PATH=""
if [ -f "$OUTPUT_PATH" ]; then
    FOUND_PATH="$OUTPUT_PATH"
else
    for pattern in "${ALT_PATHS[@]}"; do
        # Use find to handle wildcards safely
        found_file=$(find $(dirname "$pattern") -name "$(basename "$pattern")" -print -quit 2>/dev/null)
        if [ -n "$found_file" ]; then
            FOUND_PATH="$found_file"
            echo "Found alternative output: $found_file"
            break
        fi
    done
fi

if [ -z "$FOUND_PATH" ]; then
    echo "Output file not found at any expected location"
    # Create empty result
    cat > "$RESULT_FILE" << EOF
{
    "file_exists": false,
    "file_path": "",
    "valid_geojson": false,
    "feature_count": 0,
    "geometry_types": [],
    "has_attributes": false,
    "attribute_names": [],
    "has_station_attributes": false,
    "station_names_found": [],
    "file_size_bytes": 0,
    "created_after_task_start": false,
    "timestamp": "$(date -Iseconds)"
}
EOF
else
    echo "Found output file: $FOUND_PATH"
    echo "File size: $(stat -c%s "$FOUND_PATH") bytes"
    
    # Analyze the GeoJSON using Python
    # We use a python heredoc to perform robust verification of the JSON structure
    python3 << PYEOF
import json
import os
import sys

result = {
    "file_exists": True,
    "file_path": "$FOUND_PATH",
    "valid_geojson": False,
    "feature_count": 0,
    "geometry_types": [],
    "has_attributes": False,
    "attribute_names": [],
    "has_station_attributes": False,
    "station_names_found": [],
    "file_size_bytes": 0,
    "created_after_task_start": False,
    "timestamp": "$(date -Iseconds)"
}

try:
    file_path = "$FOUND_PATH"
    result["file_size_bytes"] = os.path.getsize(file_path)

    # Check creation time vs task start
    task_start = int("$TASK_START")
    file_mtime = int(os.path.getmtime(file_path))
    result["created_after_task_start"] = file_mtime >= task_start

    with open(file_path, "r") as f:
        data = json.load(f)

    if data.get("type") == "FeatureCollection" and "features" in data:
        result["valid_geojson"] = True
        features = data["features"]
        result["feature_count"] = len(features)

        geom_types = set()
        all_attrs = set()
        station_names = []
        has_station_attrs = False

        known_stations = ["Alviso", "Guadalupe", "San Leandro", "San Lorenzo",
                          "Coyote", "Alameda", "Oakland", "Niles"]

        for feat in features:
            # Check geometry
            geom = feat.get("geometry")
            if geom and geom.get("type"):
                geom_types.add(geom["type"])

            # Check properties
            props = feat.get("properties", {})
            if props:
                for key, val in props.items():
                    all_attrs.add(key)

                    # Check for station-specific attributes (fuzzy matching for column names)
                    if any(x in key.lower() for x in ["ph", "dissolved", "temperature", "station"]):
                        has_station_attrs = True

                    # Check for station names in string values
                    if val and isinstance(val, str):
                        for name in known_stations:
                            if name.lower() in val.lower():
                                station_names.append(val)
                                has_station_attrs = True
                                break

                    # Check for numeric values matching CSV measurements
                    if key.lower() == "ph" and isinstance(val, (int, float)):
                        if 7.0 <= val <= 9.0:
                            has_station_attrs = True

        result["geometry_types"] = sorted(list(geom_types))
        result["attribute_names"] = sorted(list(all_attrs))
        result["has_attributes"] = len(all_attrs) > 0
        result["has_station_attributes"] = has_station_attrs
        result["station_names_found"] = list(set(station_names))

except Exception as e:
    result["error"] = str(e)

with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)
PYEOF
fi

# Ensure permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"