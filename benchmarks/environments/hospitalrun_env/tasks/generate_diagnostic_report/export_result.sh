#!/bin/bash
echo "=== Exporting generate_diagnostic_report result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot (Primary Evidence)
take_screenshot /tmp/task_final.png

# Capture Browser URL (Secondary Evidence)
# Try to get the URL from the address bar if possible, or just the window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "final_window_title": "$WINDOW_TITLE",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="