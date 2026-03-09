#!/bin/bash
# export_result.sh for configure_sensor_node_api@1

echo "=== Exporting configure_sensor_node_api results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# Gather Database State (Ground Truth)
# -----------------------------------------------------------------------

# 1. Inputs Check
INPUT_COUNT=$(db_query "SELECT COUNT(*) FROM input WHERE nodeid='office_env'" 2>/dev/null)
INPUT_DETAILS=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e \
    "SELECT name, processList FROM input WHERE nodeid='office_env'" 2>/dev/null)

# Format input details as JSON array
# Example output from mysql:
# temperature  1:15
# humidity     1:16
INPUTS_JSON="[]"
if [ -n "$INPUT_DETAILS" ]; then
    # Use python to safely format mysql output to JSON
    INPUTS_JSON=$(python3 -c "
import sys, json
lines = sys.stdin.readlines()
data = []
for line in lines:
    parts = line.strip().split('\t')
    if len(parts) >= 1:
        obj = {'name': parts[0], 'processList': parts[1] if len(parts) > 1 else ''}
        data.append(obj)
print(json.dumps(data))
" <<< "$INPUT_DETAILS")
fi

# 2. Feeds Check
FEED_COUNT=$(db_query "SELECT COUNT(*) FROM feeds WHERE tag='office_env'" 2>/dev/null)
FEED_DETAILS=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e \
    "SELECT id, name, tag, engine, unit, value, UNIX_TIMESTAMP(time) FROM feeds WHERE tag='office_env'" 2>/dev/null)

# Format feed details as JSON array
FEEDS_JSON="[]"
if [ -n "$FEED_DETAILS" ]; then
    FEEDS_JSON=$(python3 -c "
import sys, json
lines = sys.stdin.readlines()
data = []
for line in lines:
    parts = line.strip().split('\t')
    if len(parts) >= 7:
        try:
            val = float(parts[5]) if parts[5] != 'NULL' else None
        except:
            val = None
        
        obj = {
            'id': parts[0],
            'name': parts[1],
            'tag': parts[2],
            'engine': parts[3],
            'unit': parts[4],
            'value': val,
            'timestamp': parts[6]
        }
        data.append(obj)
print(json.dumps(data))
" <<< "$FEED_DETAILS")
fi

# -----------------------------------------------------------------------
# Gather File System State (Agent Output)
# -----------------------------------------------------------------------
CONFIG_FILE="/home/ga/sensor_config.json"
CONFIG_EXISTS="false"
CONFIG_CONTENT="{}"
CONFIG_MTIME="0"

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    # Read content, ensuring it's valid JSON (or empty object if invalid)
    if python3 -m json.tool "$CONFIG_FILE" >/dev/null 2>&1; then
        CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    else
        echo "Warning: output file is not valid JSON"
    fi
fi

# -----------------------------------------------------------------------
# Create Final Export JSON
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "database": {
        "input_count": ${INPUT_COUNT:-0},
        "inputs": $INPUTS_JSON,
        "feed_count": ${FEED_COUNT:-0},
        "feeds": $FEEDS_JSON
    },
    "file_system": {
        "config_exists": $CONFIG_EXISTS,
        "config_mtime": $CONFIG_MTIME,
        "config_content": $CONFIG_CONTENT
    }
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="