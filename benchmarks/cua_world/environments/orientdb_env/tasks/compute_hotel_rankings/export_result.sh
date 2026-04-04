#!/bin/bash
echo "=== Exporting compute_hotel_rankings results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/top_tier_hotels.json"

# 1. Check Output File
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Database Schema (ImpactScore property)
echo "Checking schema for ImpactScore..."
SCHEMA_CHECK=$(orientdb_query "demodb" "SELECT FROM (SELECT expand(properties) FROM (SELECT expand(classes) FROM metadata:schema) WHERE name = 'Hotels') WHERE name = 'ImpactScore'")
PROPERTY_EXISTS=$(echo "$SCHEMA_CHECK" | python3 -c "import sys, json; res=json.load(sys.stdin).get('result', []); print('true' if len(res) > 0 else 'false')" 2>/dev/null || echo "false")

# 3. Verify Calculations: Fetch sample data directly from DB
# We fetch Name, Stars, ImpactScore, and the actual edge count to verify the formula in python
echo "Fetching sample data for verification..."
SAMPLE_DATA=$(orientdb_query "demodb" "SELECT Name, Stars, ImpactScore, in('HasStayed').size() as EdgeCount FROM Hotels LIMIT 50")

# 4. Check Data Coverage (How many nulls?)
NULL_COUNT=$(orientdb_query "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE ImpactScore IS NULL" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt', -1))" 2>/dev/null || echo "-1")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# We embed the SAMPLE_DATA json string into our result json carefully
# Python helper to construct the final JSON safely
python3 -c "
import json
import sys

try:
    sample_data_raw = '''$SAMPLE_DATA'''
    sample_data = json.loads(sample_data_raw).get('result', [])
except:
    sample_data = []

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'output_size_bytes': $OUTPUT_SIZE,
    'property_exists': $PROPERTY_EXISTS,
    'null_score_count': int('$NULL_COUNT'),
    'db_sample': sample_data
}
print(json.dumps(result))
" > "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="