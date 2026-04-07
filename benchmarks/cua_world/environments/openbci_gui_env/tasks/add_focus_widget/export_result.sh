#!/bin/bash
echo "=== Exporting add_focus_widget results ==="

# 1. Capture Final Screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if OpenBCI is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null || pgrep -f "processing.core.PApplet" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Create JSON Result
# We rely heavily on VLM for the visual verification of the widget.
# This JSON provides supporting evidence.

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "initial_screenshot_path": "/tmp/task_initial.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"