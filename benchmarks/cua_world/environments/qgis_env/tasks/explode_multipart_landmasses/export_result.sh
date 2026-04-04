#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

EXPORT_DIR="/home/ga/GIS_Data/exports"
OUTPUT_FILE="$EXPORT_DIR/countries_singlepart.geojson"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output file exists (allow flexible naming)
if [ ! -f "$OUTPUT_FILE" ]; then
    ALT_FILE=$(find "$EXPORT_DIR" -name "*singlepart*.geojson" -o -name "*exploded*.geojson" | head -n 1)
    if [ -n "$ALT_FILE" ]; then
        OUTPUT_FILE="$ALT_FILE"
    fi
fi

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_feature_count.txt 2>/dev/null || echo "0")

# Run analysis script
python3 << PYEOF
import json
import os
import sys

output_file = "$OUTPUT_FILE"
initial_count = int("$INITIAL_COUNT")
task_start = int("$TASK_START")

result = {
    "file_exists": False,
    "valid_geojson": False,
    "feature_count": 0,
    "feature_count_increased": False,
    "geometry_types": {},
    "all_polygon": False,
    "attributes_preserved": False,
    "file_newly_created": False
}

if os.path.exists(output_file):
    result["file_exists"] = True
    
    # Check creation time
    try:
        mtime = os.path.getmtime(output_file)
        if mtime > task_start:
            result["file_newly_created"] = True
    except:
        pass

    try:
        with open(output_file, 'r') as f:
            data = json.load(f)
        
        if data.get('type') == 'FeatureCollection':
            result["valid_geojson"] = True
            features = data.get('features', [])
            count = len(features)
            result["feature_count"] = count
            
            # Check feature count increase
            # If initial count is 0 (fallback), assume > 10 is success
            threshold = initial_count if initial_count > 0 else 10
            if count > threshold:
                result["feature_count_increased"] = True
            
            # Check geometries and attributes
            geoms = {}
            has_attrs = False
            
            for feat in features:
                # Geometry check
                gtype = feat.get('geometry', {}).get('type', 'Unknown')
                geoms[gtype] = geoms.get(gtype, 0) + 1
                
                # Attribute check (look for common country fields)
                props = feat.get('properties', {})
                keys = [k.upper() for k in props.keys()]
                if 'NAME' in keys or 'ADMIN' in keys or 'ISO_A3' in keys:
                    has_attrs = True
            
            result["geometry_types"] = geoms
            result["attributes_preserved"] = has_attrs
            
            # Strictly speaking, result should be Polygon. 
            # Some tools might output MultiPolygon with single part, which is acceptable but less ideal.
            # We check if MultiPolygon count is low or zero relative to Polygon.
            poly_count = geoms.get('Polygon', 0)
            multi_count = geoms.get('MultiPolygon', 0)
            
            # Pass if predominantly Polygon
            if poly_count > 0 and multi_count == 0:
                result["all_polygon"] = True
            elif poly_count > (count * 0.9): 
                # Allow small margin of error or single-part multis
                result["all_polygon"] = True
                
    except Exception as e:
        print(f"Error parsing GeoJSON: {e}")

# Save result
with open("$RESULT_FILE", 'w') as f:
    json.dump(result, f)

PYEOF

# Fix permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

cat "$RESULT_FILE"
echo "=== Export complete ==="