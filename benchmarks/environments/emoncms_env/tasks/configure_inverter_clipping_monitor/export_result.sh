#!/bin/bash
echo "=== Exporting Inverter Clipping Monitor Results ==="

source /workspace/scripts/task_utils.sh

# Record end time and capture final screenshot
TASK_END=$(date +%s)
take_screenshot /tmp/task_final.png

# 1. Fetch Input Configuration
# We need the processList for the 'solar_pv' input
INPUT_DATA=$(db_query "SELECT id, name, processList FROM input WHERE nodeid='home' AND name='solar_pv'" 2>/dev/null)
# Output format: ID \t NAME \t PROCESSLIST (e.g. "1:12,7:-3600,8:0")
INPUT_ID=$(echo "$INPUT_DATA" | cut -f1)
PROCESS_LIST_STR=$(echo "$INPUT_DATA" | cut -f3)

echo "Input ID: $INPUT_ID"
echo "Process List String: $PROCESS_LIST_STR"

# 2. Fetch Feeds
# We need to map Feed IDs (from processList) to Feed Names to verify they are correct
# Format: id, name, engine, interval
FEEDS_JSON=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e "SELECT id, name, engine, \`interval\` FROM feeds WHERE userid=1" | \
    jq -R -s -c 'split("\n") | map(select(length > 0)) | map(split("\t")) | map({"id": .[0], "name": .[1], "engine": .[2], "interval": .[3]})')

# 3. Fetch Process Definitions (Optional but helpful for mapping IDs)
# Emoncms stores process definitions in the code, but sometimes in DB.
# We will use hardcoded mappings in the verifier for standard Emoncms processes.

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/clipping_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_end_timestamp": $TASK_END,
    "input": {
        "id": "$INPUT_ID",
        "name": "solar_pv",
        "process_list_str": "$PROCESS_LIST_STR"
    },
    "feeds": $FEEDS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/task_result.json
echo "=== Export complete ==="