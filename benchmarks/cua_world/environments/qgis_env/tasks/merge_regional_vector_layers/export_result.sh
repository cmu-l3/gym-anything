#!/bin/bash
echo "=== Exporting merge_regional_vector_layers result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Basic file checks
OUTPUT_PATH="/home/ga/GIS_Data/exports/merged_countries.geojson"
GROUND_TRUTH="/tmp/ground_truth_counts.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Deep Python Analysis (GeoJSON structure, feature counts, attributes)
ANALYSIS_JSON=$(python3 << PYEOF
import json
import sys
import os

output_path = "$OUTPUT_PATH"
gt_path = "$GROUND_TRUTH"

result = {
    "is_valid_json": False,
    "is_feature_collection": False,
    "feature_count": 0,
    "expected_count": 0,
    "geometry_types": [],
    "attributes_found": [],
    "continents_present": [],
    "crs_match": False
}

# Load ground truth
if os.path.exists(gt_path):
    with open(gt_path, 'r') as f:
        gt = json.load(f)
        result["expected_count"] = gt.get("total_expected", 0)

# Analyze output
if os.path.exists(output_path):
    try:
        with open(output_path, 'r') as f:
            data = json.load(f)
            result["is_valid_json"] = True
            
            if data.get("type") == "FeatureCollection":
                result["is_feature_collection"] = True
                features = data.get("features", [])
                result["feature_count"] = len(features)
                
                # Check CRS (GeoJSON standard is 4326 implies null or OGC URN)
                # But QGIS explicitly writes it usually
                crs = data.get("crs", {})
                if not crs or "EPSG:4326" in str(crs) or "CRS84" in str(crs):
                    result["crs_match"] = True

                # Check geometries and attributes
                geoms = set()
                attrs = set()
                continents = set()
                
                for feat in features[:100]: # Sample first 100 for speed
                    # Geometry
                    g = feat.get("geometry")
                    if g:
                        geoms.add(g.get("type"))
                    
                    # Properties
                    props = feat.get("properties", {})
                    for k in props.keys():
                        attrs.add(k)
                    
                    # Check continent values
                    cont = props.get("CONTINENT")
                    if cont:
                        continents.add(cont)
                
                result["geometry_types"] = list(geoms)
                result["attributes_found"] = list(attrs)
                result["continents_present"] = list(continents)
                
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Save result to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="