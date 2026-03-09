#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting derive_residual_power results ==="

# Stop traffic generator
if [ -f /tmp/traffic_gen.pid ]; then
    kill $(cat /tmp/traffic_gen.pid) 2>/dev/null || true
fi

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Emoncms State
# We need both Feeds and Inputs to verify the math
feeds_json=$(emoncms_api "feed/list.json" "")
inputs_json=$(emoncms_api "input/list.json" "")

# 3. Get Process List for 'main_power' input (to verify order programmatically if needed)
# Using DB query as API doesn't always show raw process list easily
MAIN_INPUT_ID=$(echo "$inputs_json" | jq '.[] | select(.nodeid==10 and .name=="main_power") | .id')
PROCESS_LIST_RAW=""
if [ -n "$MAIN_INPUT_ID" ]; then
    PROCESS_LIST_RAW=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e "SELECT processList FROM input WHERE id=$MAIN_INPUT_ID")
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": $(date +%s),
    "feeds": $feeds_json,
    "inputs": $inputs_json,
    "main_input_process_list": "$PROCESS_LIST_RAW"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"