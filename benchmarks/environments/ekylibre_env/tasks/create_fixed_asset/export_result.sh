#!/bin/bash
set -e
echo "=== Exporting create_fixed_asset results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_fixed_asset_count.txt 2>/dev/null || echo "0")

# Query current count
FINAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM fixed_assets;" 2>/dev/null || echo "0")

# Query the specific record created by the agent
# searching by name pattern
RECORD_QUERY="SELECT id, name, amount, started_on, stopped_on, depreciation_method, depreciable_amount, depreciation_percentage, currency, created_at FROM fixed_assets WHERE name ILIKE '%john deere%6120%' ORDER BY created_at DESC LIMIT 1;"

# Execute query
# Format output as pipe-separated values for easier parsing, or just raw
RECORD_DATA=$(ekylibre_db_query "$RECORD_QUERY")

# Check if a record was found
RECORD_FOUND="false"
if [ -n "$RECORD_DATA" ]; then
    RECORD_FOUND="true"
fi

# Prepare JSON output using python to safely construct JSON
python3 << EOF > /tmp/task_result.json
import json
import sys

try:
    record_found = "$RECORD_FOUND" == "true"
    record_data_raw = "$RECORD_DATA"
    
    result = {
        "task_start": $TASK_START,
        "task_end": $TASK_END,
        "initial_count": int("$INITIAL_COUNT"),
        "final_count": int("$FINAL_COUNT"),
        "record_found": record_found,
        "record": {},
        "screenshot_path": "/tmp/task_final.png"
    }

    if record_found and record_data_raw:
        # Expected format from psql -A -t is pipe separated if multiple cols, 
        # but here we requested specific columns. 
        # Since psql output format can vary, we'll rely on the fact that we requested specific columns.
        # However, psql -t -A uses pipe | as default separator
        
        parts = record_data_raw.strip().split('|')
        if len(parts) >= 10:
            result["record"] = {
                "id": parts[0],
                "name": parts[1],
                "amount": parts[2],
                "started_on": parts[3],
                "stopped_on": parts[4],
                "depreciation_method": parts[5],
                "depreciable_amount": parts[6],
                "depreciation_percentage": parts[7],
                "currency": parts[8],
                "created_at": parts[9]
            }

    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({"error": str(e), "record_found": False}, indent=2))
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="