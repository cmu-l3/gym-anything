#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if DisruptiveUser process is still running
# If the agent used 'kill' or closed the browser via terminal, this would be false.
# If they kicked via UI, the browser should still be open (showing 'Kicked' screen).
DISRUPTIVE_PID=$(cat /tmp/disruptive_pid.txt 2>/dev/null)
DISRUPTIVE_PROCESS_RUNNING="false"

if [ -n "$DISRUPTIVE_PID" ] && ps -p "$DISRUPTIVE_PID" > /dev/null; then
    DISRUPTIVE_PROCESS_RUNNING="true"
elif pgrep -f "epiphany" > /dev/null; then
    # PID might have changed if wrapper script, fallback to name
    DISRUPTIVE_PROCESS_RUNNING="true"
fi

# 2. Check if Agent Firefox is still running
AGENT_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "disruptive_process_running": $DISRUPTIVE_PROCESS_RUNNING,
    "agent_running": $AGENT_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="