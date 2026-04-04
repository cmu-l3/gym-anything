#!/bin/bash
echo "=== Exporting join_csv_attributes_by_field result ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_FILE="/home/ga/GIS_Data/exports/countries_with_statistics.geojson"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check basics
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    # Check for likely alternatives (user might have saved elsewhere or with different name)
    ALT_FILE=$(find /home/ga/GIS_Data -name "*joined*" -o -name "*statistics*" | grep ".geojson$" | head -n 1)
    if [ -n "$ALT_FILE" ] && [ -f "$ALT_FILE" ]; then
        echo "Found alternative file: $ALT_FILE"
        OUTPUT_FILE="$ALT_FILE"
        OUTPUT_EXISTS="true"
        OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
        OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
        if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    fi
fi

# 3. Analyze Content with Python
# We inspect the GeoJSON to verify the join actually happened (fields exist) and geometry is preserved.

ANALYSIS_JSON=$(python3 << PYEOF
import json
import os
import sys

file_path = "$OUTPUT_FILE"
result = {
    "valid_geojson": False,
    "feature_count": 0,
    "has_geometry": False,
    "fields_found": [],
    "pop_est_found": False,
    "gdp_md_found": False,
    "usa_pop_check": 0,
    "chn_pop_check": 0
}

if os.path.exists(file_path):
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
            
        if data.get('type') == 'FeatureCollection' and 'features' in data:
            result['valid_geojson'] = True
            features = data['features']
            result['feature_count'] = len(features)
            
            if result['feature_count'] > 0:
                # Check first feature for fields
                props = features[0].get('properties', {})
                keys = [k.upper() for k in props.keys()]
                result['fields_found'] = list(props.keys())
                
                # Check for joined fields (allow partial matching for joined prefixes)
                # e.g. "country_statistics_POP_EST" or just "POP_EST"
                result['pop_est_found'] = any('POP_EST' in k for k in keys)
                result['gdp_md_found'] = any('GDP_MD' in k for k in keys)
                
                # Check geometry type
                geom_type = features[0].get('geometry', {}).get('type', '')
                result['has_geometry'] = geom_type in ['Polygon', 'MultiPolygon']
                
                # Spot checks for specific countries
                for feat in features:
                    p = feat.get('properties', {})
                    iso = p.get('ISO_A3', '')
                    
                    # Find population value (handle varying field names)
                    pop_val = 0
                    for k, v in p.items():
                        if 'POP_EST' in k.upper():
                            try:
                                pop_val = float(v)
                                break
                            except:
                                pass
                                
                    if iso == 'USA':
                        result['usa_pop_check'] = pop_val
                    elif iso == 'CHN':
                        result['chn_pop_check'] = pop_val
                        
    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Save Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_FILE",
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="