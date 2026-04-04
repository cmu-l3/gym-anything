#!/bin/bash
echo "=== Exporting Task Result: Block Schedule Meeting ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Parameters from task definition
TARGET_DATE="2026-03-20"
PROVIDER_NO="999998"

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the database for appointments on the target date
# We get all columns needed for verification: start_time, end_time, notes, reason, status, duration
echo "Querying database for appointments on $TARGET_DATE..."

# Using a comprehensive query to catch entries that might be stored in 'reason' OR 'notes'
# output format: start_time|end_time|duration|status|reason|notes
DB_RESULT=$(oscar_query "SELECT start_time, end_time, duration, status, reason, notes 
                         FROM appointment 
                         WHERE provider_no='$PROVIDER_NO' 
                         AND appointment_date='$TARGET_DATE' 
                         AND status != 'C' 
                         ORDER BY start_time ASC")

# Check if we got any result
if [ -n "$DB_RESULT" ]; then
    ENTRY_FOUND="true"
else
    ENTRY_FOUND="false"
fi

# 3. Create JSON output
# We need to be careful with newlines/special chars in SQL output when creating JSON strings
# We'll use python to safely construct the JSON if possible, or careful bash escaping

# Create a temporary python script to generate the JSON
cat <<EOF > /tmp/generate_result_json.py
import json
import sys

entry_found = "$ENTRY_FOUND" == "true"
entries = []

raw_data = """$DB_RESULT"""

if entry_found and raw_data.strip():
    for line in raw_data.strip().split('\n'):
        parts = line.split('\t')
        if len(parts) >= 6:
            entries.append({
                "start_time": parts[0],
                "end_time": parts[1],
                "duration": parts[2],
                "status": parts[3],
                "reason": parts[4],
                "notes": parts[5]
            })

result = {
    "entry_found": entry_found,
    "entries": entries,
    "target_date": "$TARGET_DATE",
    "provider_no": "$PROVIDER_NO",
    "screenshot_path": "/tmp/task_final.png"
}

print(json.dumps(result, indent=2))
EOF

# Run python script and save output
python3 /tmp/generate_result_json.py > /tmp/task_result.json

# Log the result for debugging
cat /tmp/task_result.json

# Fix permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="