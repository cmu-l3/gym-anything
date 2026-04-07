#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load baseline info
PROVIDER_ID=$(cat /tmp/target_provider_id.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Get current scheduler count
CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM scheduler" 2>/dev/null || echo "0")

# Dump all schedule records for the provider on the target date.
# We use Python to parse TSV to JSON to robustly handle FreeMED's table structure.
mysql -u freemed -pfreemed freemed -e "SELECT * FROM scheduler WHERE calphysician=$PROVIDER_ID AND caldateof='2026-03-20'" 2>/dev/null | python3 -c '
import sys, json
raw = sys.stdin.read().strip()
if not raw:
    print(json.dumps([]))
else:
    lines = raw.split("\n")
    if len(lines) < 2:
        print(json.dumps([]))
    else:
        headers = lines[0].split("\t")
        res = [dict(zip(headers, line.split("\t"))) for line in lines[1:]]
        print(json.dumps(res))
' > /tmp/sched_records.json

# Build the final output JSON safely into a temporary file
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "provider_id": "$PROVIDER_ID",
    "records": $(cat /tmp/sched_records.json)
}
EOF

# Move to final location, managing permissions properly
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="