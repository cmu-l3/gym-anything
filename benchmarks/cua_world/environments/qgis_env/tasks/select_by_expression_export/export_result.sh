#!/bin/bash
echo "=== Exporting Select by Expression Export result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Identify Output File
EXPORT_DIR="/home/ga/GIS_Data/exports"
# Allow for slight variations in naming, though instructions were specific
OUTPUT_FILE=""
if [ -f "$EXPORT_DIR/major_megacities.geojson" ]; then
    OUTPUT_FILE="$EXPORT_DIR/major_megacities.geojson"
elif [ -f "$EXPORT_DIR/major_megacities.json" ]; then
    OUTPUT_FILE="$EXPORT_DIR/major_megacities.json"
else
    # Fallback: find most recently modified geojson in exports
    OUTPUT_FILE=$(find "$EXPORT_DIR" -name "*.geojson" -mmin -10 | head -n 1)
fi

echo "Identified output file: $OUTPUT_FILE"

# 3. Analyze Results using Python
# We perform the analysis inside the container to avoid copying large files
# and to utilize local libraries.
PYTHON_SCRIPT=$(cat << 'EOF'
import json
import os
import sys
import time

output_path = sys.argv[1]
start_time = float(sys.argv[2])

result = {
    "file_exists": False,
    "file_path": output_path,
    "valid_geojson": False,
    "feature_count": 0,
    "all_correct_threshold": False,
    "incorrect_features": 0,
    "known_cities_found": [],
    "is_new_file": False,
    "file_size": 0
}

if output_path and os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    # Check timestamp (Anti-gaming)
    mtime = os.path.getmtime(output_path)
    if mtime > start_time:
        result["is_new_file"] = True

    try:
        with open(output_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        if data.get('type') == 'FeatureCollection' and 'features' in data:
            result["valid_geojson"] = True
            features = data['features']
            result["feature_count"] = len(features)
            
            # Check attributes
            incorrect = 0
            correct = 0
            found_cities = []
            
            # List of known mega cities to check against
            targets = ["Tokyo", "Delhi", "Shanghai", "São Paulo", "Mumbai", "Cairo", "Beijing", "Osaka", "New York", "Dhaka"]
            
            for feat in features:
                props = feat.get('properties', {})
                
                # Check population (handle various field name cases)
                pop = None
                for key in ['pop_max', 'POP_MAX', 'Pop_Max']:
                    if key in props:
                        pop = props[key]
                        break
                
                if pop is not None:
                    try:
                        if float(pop) > 10000000:
                            correct += 1
                        else:
                            incorrect += 1
                    except ValueError:
                        pass
                
                # Check city names
                name = props.get('name', '') or props.get('NAME', '')
                if name:
                    for t in targets:
                        if t.lower() in str(name).lower():
                            found_cities.append(t)
            
            result["all_correct_threshold"] = (incorrect == 0 and correct > 0)
            result["incorrect_features"] = incorrect
            result["known_cities_found"] = list(set(found_cities))
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
EOF
)

# Get start time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run analysis
if [ -n "$OUTPUT_FILE" ]; then
    python3 -c "$PYTHON_SCRIPT" "$OUTPUT_FILE" "$START_TIME" > /tmp/analysis_result.json
else
    echo '{"file_exists": false}' > /tmp/analysis_result.json
fi

# 4. Prepare final export JSON (Permission safe)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cp /tmp/analysis_result.json "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="