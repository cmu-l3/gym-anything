#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Live Forensic Analysis Result ==="

REPORT_PATH="/home/ga/Documents/forensic_report.json"
TRUTH_PATH="/root/.task_truth.json"

# 1. Check if report exists
REPORT_EXISTS="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
fi

# 2. Check if volume is currently mounted (Should be dismounted)
# We check slot 2 specifically or the path from truth
IS_MOUNTED="false"
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
if echo "$MOUNT_LIST" | grep -q "/home/ga/MountPoints/slot2"; then
    IS_MOUNTED="true"
fi

# 3. Get Truth Data (Read by root, echo into variable)
TRUTH_JSON=$(cat "$TRUTH_PATH" 2>/dev/null || echo "{}")

# 4. Read Agent Report (if exists)
AGENT_JSON="{}"
if [ "$REPORT_EXISTS" = "true" ]; then
    AGENT_JSON=$(cat "$REPORT_PATH")
fi

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Construct Result JSON
# We embed both agent report and truth for the verifier to compare on host
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "volume_still_mounted": $IS_MOUNTED,
    "ground_truth": $TRUTH_JSON,
    "agent_report": $AGENT_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 7. Save to readable location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="