#!/bin/bash
echo "=== Exporting Multi-Res Logging Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Kill the background generator
if [ -f /tmp/generator_pid.txt ]; then
    kill $(cat /tmp/generator_pid.txt) 2>/dev/null || true
fi

# 3. Query Database for Results

# Get the Input ID and Process List
INPUT_INFO=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e \
    "SELECT id, processList FROM input WHERE name='rack_power_main' AND userid=1")

INPUT_ID=$(echo "$INPUT_INFO" | cut -f1)
PROCESS_LIST=$(echo "$INPUT_INFO" | cut -f2)

echo "Input ID: $INPUT_ID"
echo "Process List: $PROCESS_LIST"

# Helper function to extract Feed IDs from process list
# Process list format example: "1:15,1:16" (ProcessType:FeedID)
# We look for ProcessType 1 (Log to feed)
extract_feed_ids() {
    local plist="$1"
    # grep matches "1:<number>", tr removes "1:", tr replaces newlines with spaces
    echo "$plist" | grep -oE "1:[0-9]+" | tr -d '1:' | tr '\n' ' '
}

FEED_IDS=$(extract_feed_ids "$PROCESS_LIST")
echo "Extracted Feed IDs: $FEED_IDS"

# 4. Construct JSON with Feed Details
# We need to look up details for each feed ID found in the chain
FEED_DETAILS="[]"

if [ -n "$FEED_IDS" ]; then
    # Create a temporary SQL script to fetch details
    SQL_WHERE="id IN ($(echo $FEED_IDS | sed 's/ /,/g'))"
    
    # JSON_OBJECT is available in newer MySQL/MariaDB, but let's stick to safe CSV parsing
    RAW_FEEDS=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e \
        "SELECT id, name, \`interval\` FROM feeds WHERE $SQL_WHERE")
    
    # Convert CSV-like output to JSON array manually using jq or python
    # Using python for reliability
    FEED_DETAILS=$(python3 -c "
import sys
import json
raw = '''$RAW_FEEDS'''
feeds = []
for line in raw.strip().split('\n'):
    if line:
        parts = line.split('\t')
        if len(parts) >= 3:
            feeds.append({
                'id': int(parts[0]),
                'name': parts[1],
                'interval': int(parts[2])
            })
print(json.dumps(feeds))
")
fi

# 5. Export result to JSON
cat > /tmp/task_result.json << JSON_EOF
{
    "input_id": "$INPUT_ID",
    "process_list_string": "$PROCESS_LIST",
    "feeds_found": $FEED_DETAILS,
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
JSON_EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json