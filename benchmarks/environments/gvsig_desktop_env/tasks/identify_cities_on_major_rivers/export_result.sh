#!/bin/bash
echo "=== Exporting identify_cities_on_major_rivers result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_SHP="/home/ga/gvsig_data/exports/river_cities.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/river_cities.dbf"
INPUT_CITIES_DBF="/home/ga/gvsig_data/cities/ne_110m_populated_places.dbf"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if file exists
if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    # Check timestamp
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    CREATED_DURING_TASK="false"
fi

# Run Python script to analyze shapefile content (using pyshp)
# We calculate counts and verify it's a subset
python3 -c "
import shapefile
import json
import sys
import os

result = {
    'output_exists': '$OUTPUT_EXISTS' == 'true',
    'created_during_task': '$CREATED_DURING_TASK' == 'true',
    'output_count': 0,
    'input_count': 0,
    'is_subset': False,
    'valid_shapefile': False,
    'error': None
}

try:
    if result['output_exists']:
        # Read Output
        try:
            sf_out = shapefile.Reader('$OUTPUT_SHP')
            result['output_count'] = len(sf_out.records())
            result['valid_shapefile'] = True
        except Exception as e:
            result['error'] = f'Invalid output shapefile: {str(e)}'

        # Read Input (to compare)
        if os.path.exists('$INPUT_CITIES_DBF'):
            sf_in = shapefile.Reader('$INPUT_CITIES_DBF')
            result['input_count'] = len(sf_in.records())
            
            # Logic check: result should be a subset (less than total, but > 0)
            if 0 < result['output_count'] < result['input_count']:
                result['is_subset'] = True
            elif result['output_count'] == result['input_count']:
                result['error'] = 'Output contains ALL cities (filtering likely failed)'
            elif result['output_count'] == 0:
                result['error'] = 'Output contains NO cities'
        else:
            result['error'] = 'Input cities DBF not found for comparison'

except Exception as e:
    result['error'] = str(e)

# Write result to file
with open('/tmp/analysis_result.json', 'w') as f:
    json.dump(result, f)
"

# Merge analysis with basic info
cat > /tmp/task_result.json << EOF
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Merge the python analysis into the main result file
if [ -f /tmp/analysis_result.json ]; then
    python3 -c "
import json
with open('/tmp/task_result.json', 'r') as f1:
    base = json.load(f1)
with open('/tmp/analysis_result.json', 'r') as f2:
    analysis = json.load(f2)
base.update(analysis)
with open('/tmp/task_result.json', 'w') as f_out:
    json.dump(base, f_out)
"
fi

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="