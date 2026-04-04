#!/bin/bash
echo "=== Exporting migrate_hotel_type_to_tags results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- DATA EXTRACTION ---

# 1. Schema Information
echo "Extracting schema..."
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 2. Data Verification Query
# Fetch the Name and Tags (and Type if it still exists) for our test cases
echo "Extracting test records..."
DATA_QUERY="SELECT Name, Tags, Type FROM Hotels WHERE Name IN ['Copacabana Palace', 'Terme di Saturnia Spa', 'Hotel Artemide', 'Tivoli Ecoresort Praia do Forte']"
DATA_JSON=$(orientdb_sql "demodb" "$DATA_QUERY")

# 3. Aggregates
# Check if any hotel has empty tags (should ideally not happen if migration worked)
EMPTY_TAGS_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Hotels WHERE Tags IS NULL OR Tags.size() = 0" | \
    python3 -c "import sys, json; print(json.load(sys.stdin).get('result', [{}])[0].get('cnt', 0))" 2>/dev/null || echo "0")

# --- BUILD RESULT JSON ---

# Use python to construct the final JSON to avoid bash quoting hell
python3 << EOF
import json
import sys
import time

try:
    # Load Schema
    schema_raw = '$SCHEMA_JSON'
    schema_data = json.loads(schema_raw) if schema_raw else {}
    
    # Load Data
    data_raw = '$DATA_JSON'
    data_data = json.loads(data_raw) if data_raw else {}
    
    hotels_class = next((c for c in schema_data.get('classes', []) if c['name'] == 'Hotels'), {})
    properties = {p['name']: p for p in hotels_class.get('properties', [])}
    
    result = {
        "timestamp": "$(date -Iseconds)",
        "task_start": $TASK_START,
        "task_end": $TASK_END,
        "schema": {
            "has_tags_property": "Tags" in properties,
            "tags_type": properties.get("Tags", {}).get("type", "UNKNOWN"),
            "has_type_property": "Type" in properties
        },
        "data": data_data.get("result", []),
        "empty_tags_count": int("$EMPTY_TAGS_COUNT"),
        "screenshot_path": "/tmp/task_final.png"
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f"Error building JSON: {e}")
    # Create failure JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)

EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="