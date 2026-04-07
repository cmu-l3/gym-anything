#!/bin/bash
echo "=== Exporting simulate_ridehailing_fleet result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

WORK_DIR="/home/ga/SUMO_Scenarios/ridehailing"

# Check if essential files exist
PERSONS_EXISTS=$([ -f "$WORK_DIR/persons.rou.xml" ] && echo "true" || echo "false")
TAXIS_EXISTS=$([ -f "$WORK_DIR/taxis.add.xml" ] && echo "true" || echo "false")
CFG_EXISTS=$([ -f "$WORK_DIR/taxi.sumocfg" ] && echo "true" || echo "false")
TRIPINFO_EXISTS=$([ -f "$WORK_DIR/tripinfos.xml" ] && echo "true" || echo "false")

# Verify tripinfo was created during the task
TRIPINFO_DURING_TASK="false"
if [ "$TRIPINFO_EXISTS" = "true" ]; then
    TRIPINFO_MTIME=$(stat -c %Y "$WORK_DIR/tripinfos.xml" 2>/dev/null || echo "0")
    if [ "$TRIPINFO_MTIME" -gt "$TASK_START" ]; then
        TRIPINFO_DURING_TASK="true"
    fi
fi

# Extract ground truth waiting time from the generated tripinfos.xml
GT_WAIT="-1"
RIDE_COUNT="0"

if [ "$TRIPINFO_DURING_TASK" = "true" ]; then
    # Use Python to safely parse XML and average the waiting times
    PARSED_DATA=$(python3 << 'EOF'
import xml.etree.ElementTree as ET
import sys
import json

try:
    tree = ET.parse('/home/ga/SUMO_Scenarios/ridehailing/tripinfos.xml')
    rides = tree.findall('.//personinfo/ride')
    wait_times = [float(r.get('waitingTime', 0)) for r in rides]
    if wait_times:
        avg_wait = sum(wait_times) / len(wait_times)
        print(json.dumps({"count": len(wait_times), "wait": avg_wait}))
    else:
        print(json.dumps({"count": 0, "wait": -1}))
except Exception as e:
    print(json.dumps({"count": 0, "wait": -1}))
EOF
    )
    GT_WAIT=$(echo "$PARSED_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('wait', -1))" 2>/dev/null)
    RIDE_COUNT=$(echo "$PARSED_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('count', 0))" 2>/dev/null)
fi

# Extract agent's reported waiting time
WAIT_TXT_EXISTS="false"
AGENT_WAIT="-1"
WAIT_TXT_FILE="$WORK_DIR/average_wait.txt"

if [ -f "$WAIT_TXT_FILE" ]; then
    WAIT_TXT_EXISTS="true"
    WAIT_MTIME=$(stat -c %Y "$WAIT_TXT_FILE" 2>/dev/null || echo "0")
    
    if [ "$WAIT_MTIME" -gt "$TASK_START" ]; then
        # Grab first numeric pattern found in file
        AGENT_WAIT=$(cat "$WAIT_TXT_FILE" | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "-1")
        if [ -z "$AGENT_WAIT" ]; then AGENT_WAIT="-1"; fi
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "persons_rou": $PERSONS_EXISTS,
        "taxis_add": $TAXIS_EXISTS,
        "taxi_cfg": $CFG_EXISTS,
        "tripinfo": $TRIPINFO_EXISTS,
        "tripinfo_during_task": $TRIPINFO_DURING_TASK,
        "average_wait_txt": $WAIT_TXT_EXISTS
    },
    "metrics": {
        "ride_count": $RIDE_COUNT,
        "gt_wait_time": $GT_WAIT,
        "agent_wait_time": $AGENT_WAIT
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="