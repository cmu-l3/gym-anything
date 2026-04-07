#!/bin/bash
echo "=== Exporting configure_scmv_custom_map_layer result ==="

# Record end time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

BNA_FILE="/home/ga/.seiscomp/bna/noto_zone.bna"
CFG_FILE="/home/ga/.seiscomp/scmv.cfg"
AGENT_SCREENSHOT="/home/ga/scmv_layer_verification.png"

# Check BNA file
BNA_EXISTS="false"
BNA_NEW="false"
BNA_CONTENT=""

if [ -f "$BNA_FILE" ]; then
    BNA_EXISTS="true"
    BNA_MTIME=$(stat -c %Y "$BNA_FILE" 2>/dev/null || echo "0")
    if [ "$BNA_MTIME" -ge "$TASK_START" ]; then
        BNA_NEW="true"
    fi
    # Safely export text content using base64 to avoid JSON escaping issues
    BNA_CONTENT=$(head -n 20 "$BNA_FILE" | base64 -w 0)
fi

# Check Configuration file
CFG_EXISTS="false"
CFG_CONTENT=""

if [ -f "$CFG_FILE" ]; then
    CFG_EXISTS="true"
    CFG_CONTENT=$(cat "$CFG_FILE" | base64 -w 0)
fi

# Check requested Screenshot
SCREENSHOT_EXISTS="false"
if [ -f "$AGENT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Check if application was running
SCMV_RUNNING="false"
if pgrep -f "scmv" > /dev/null; then
    SCMV_RUNNING="true"
fi

# Take final programmatic screenshot for trajectory validation
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/scmv_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "bna_exists": $BNA_EXISTS,
    "bna_created_during_task": $BNA_NEW,
    "bna_content_b64": "$BNA_CONTENT",
    "cfg_exists": $CFG_EXISTS,
    "cfg_content_b64": "$CFG_CONTENT",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "scmv_running": $SCMV_RUNNING
}
EOF

# Safely copy to standard path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="