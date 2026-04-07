#!/bin/bash
echo "=== Exporting XML Batch Split Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
INBOX="/home/ga/Documents/inbox"
OUTBOX="/home/ga/Documents/outbox"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Channel Creation
INITIAL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)

# Find if the specific channel exists
CHANNEL_ID=$(get_channel_id "Census_Processor")
CHANNEL_EXISTS="false"
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
fi

# 2. Check Input File Status (Should be processed/deleted/moved)
INPUT_FILE_REMAINS="false"
if [ -f "$INBOX/daily_census.xml" ]; then
    INPUT_FILE_REMAINS="true"
fi

# 3. Analyze Output Files
FILE_COUNT=0
VALID_JSON_COUNT=0
NAMES_FOUND_COUNT=0
EXPECTED_NAMES=("Valerie Tinsley" "Robert Chen" "Marcus Johnson" "Sarah O'Connor" "Elena Rodriguez")
FOUND_NAMES_JSON="[]"

if [ -d "$OUTBOX" ]; then
    # Count files created AFTER task start
    # We use python for precise timestamp comparison and JSON validation
    
    cat > /tmp/analyze_output.py << PYEOF
import os
import json
import glob
import time

outbox = "$OUTBOX"
task_start = $TASK_START
expected_names = [$(printf "'%s', " "${EXPECTED_NAMES[@]}")]
found_names = []
valid_json_files = 0
total_files = 0

files = glob.glob(os.path.join(outbox, "*"))
total_files = len(files)

for fpath in files:
    try:
        # Check timestamp
        mtime = os.path.getmtime(fpath)
        if mtime < task_start:
            continue
            
        # Check JSON validity
        with open(fpath, 'r') as f:
            content = f.read()
            data = json.loads(content)
            valid_json_files += 1
            
            # Check content
            content_str = str(data)
            for name in expected_names:
                if name in content_str and name not in found_names:
                    found_names.append(name)
                    
    except Exception:
        pass

result = {
    "total_files": total_files,
    "valid_json_count": valid_json_files,
    "found_names": found_names,
    "names_count": len(found_names)
}
print(json.dumps(result))
PYEOF

    ANALYSIS=$(python3 /tmp/analyze_output.py)
    FILE_COUNT=$(echo "$ANALYSIS" | jq .total_files)
    VALID_JSON_COUNT=$(echo "$ANALYSIS" | jq .valid_json_count)
    NAMES_FOUND_COUNT=$(echo "$ANALYSIS" | jq .names_count)
    FOUND_NAMES_JSON=$(echo "$ANALYSIS" | jq .found_names)
fi

# 4. Get API Statistics if channel exists
MESSAGES_RECEIVED=0
MESSAGES_SENT=0
if [ "$CHANNEL_EXISTS" = "true" ]; then
    STATS=$(get_channel_stats_api "$CHANNEL_ID")
    if [ -n "$STATS" ]; then
        MESSAGES_RECEIVED=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('channelStatistics',{}).get('received',0))" 2>/dev/null || echo "0")
        MESSAGES_SENT=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('channelStatistics',{}).get('sent',0))" 2>/dev/null || echo "0")
    fi
fi

# Create Result JSON
JSON_CONTENT=$(cat <<EOF
{
    "task_start_time": $TASK_START,
    "initial_channel_count": $INITIAL_COUNT,
    "current_channel_count": $CURRENT_COUNT,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "input_file_remains": $INPUT_FILE_REMAINS,
    "output_file_count": $FILE_COUNT,
    "valid_json_count": $VALID_JSON_COUNT,
    "names_found_count": $NAMES_FOUND_COUNT,
    "found_names": $FOUND_NAMES_JSON,
    "api_received": $MESSAGES_RECEIVED,
    "api_sent": $MESSAGES_SENT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"

echo "Export Complete. Result:"
cat /tmp/task_result.json