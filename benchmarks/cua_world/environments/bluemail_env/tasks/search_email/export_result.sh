#!/bin/bash
echo "=== Exporting search_email result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/bluemail_final.png

# Check if BlueMail is still running
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# Get initial matching count
INITIAL_MATCHING=$(cat /tmp/initial_matching_count 2>/dev/null || echo "0")

# Check all windows
ALL_WINDOWS=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | tr '\n' ' ' || echo "none")

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

ALL_WINDOWS_ESC=$(echo "$ALL_WINDOWS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$ALL_WINDOWS")

cat > "$TEMP_JSON" << EOF
{
    "bluemail_running": $BM_RUNNING,
    "initial_matching_count": $INITIAL_MATCHING,
    "all_windows": "$ALL_WINDOWS_ESC",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
