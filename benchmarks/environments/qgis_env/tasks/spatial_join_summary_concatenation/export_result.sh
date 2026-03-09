#!/bin/bash
echo "=== Exporting spatial_join_summary_concatenation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

EXPORT_FILE="/home/ga/GIS_Data/exports/precinct_inventory.geojson"

# 1. Check File Existence & Timestamp
FILE_EXISTS="false"
FILE_SIZE=0
FILE_NEW="false"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_FILE")
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE")
    
    if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
        FILE_NEW="true"
    fi
fi

# 2. Analyze Content using Python
# We need to check:
# - Is it a valid GeoJSON FeatureCollection?
# - Are geometries Polygons? (Should inherit from precincts)
# - Is feature count 2? (Preserves precincts)
# - Do new summary fields exist? (e.g., place_name_count, place_name_cat)
# - Are values correct?

ANALYSIS=$(python3 << 'PYEOF'
import json
import sys

output = {
    "valid_geojson": False,
    "feature_count": 0,
    "geom_type_polygon": False,
    "fields": [],
    "has_count_field": False,
    "has_concat_field": False,
    "data_accuracy": 0.0, # 0.0 to 1.0
    "details": ""
}

try:
    with open("/home/ga/GIS_Data/exports/precinct_inventory.geojson") as f:
        data = json.load(f)
    
    output["valid_geojson"] = True
    features = data.get("features", [])
    output["feature_count"] = len(features)
    
    # Check Geometry
    if features:
        types = set(f["geometry"]["type"] for f in features)
        output["geom_type_polygon"] = all(t in ["Polygon", "MultiPolygon"] for t in types)
        
        # Extract Fields
        props = features[0].get("properties", {})
        output["fields"] = list(props.keys())
        
        # Identify Summary Fields (QGIS naming varies slightly by version/tool parameters)
        # Look for 'count' and 'conc' in field names
        count_fields = [k for k in props.keys() if "count" in k.lower()]
        concat_fields = [k for k in props.keys() if "conc" in k.lower() or "cat" in k.lower() or "summary" in k.lower()]
        
        output["has_count_field"] = len(count_fields) > 0
        output["has_concat_field"] = len(concat_fields) > 0
        
        # Validate Data Accuracy
        # Ground Truth:
        # Precinct A: count 2, names Lincoln, Library
        # Precinct B: count 3, names Westside, Fire, Veterans
        
        correct_features = 0
        total_checks = 0
        
        for feat in features:
            p = feat["properties"]
            name = p.get("precinct_name", "")
            
            c_val = 0
            if count_fields:
                c_val = p.get(count_fields[0], 0)
                
            cat_val = ""
            if concat_fields:
                cat_val = str(p.get(concat_fields[0], ""))
            
            if name == "Precinct A":
                total_checks += 1
                if c_val == 2 and "Lincoln" in cat_val and "Library" in cat_val:
                    correct_features += 1
            elif name == "Precinct B":
                total_checks += 1
                if c_val == 3 and "Fire" in cat_val and "Veterans" in cat_val:
                    correct_features += 1
        
        if total_checks > 0:
            output["data_accuracy"] = correct_features / total_checks

except FileNotFoundError:
    output["details"] = "File not found"
except Exception as e:
    output["details"] = str(e)

print(json.dumps(output))
PYEOF
)

# 3. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_new": $FILE_NEW,
    "file_size": $FILE_SIZE,
    "analysis": $ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="