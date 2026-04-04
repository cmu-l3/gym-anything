#!/bin/bash
echo "=== Exporting terminate_runaway_process result ==="

# Load PIDs from setup
if [ -f /tmp/task_pids.json ]; then
    TARGET_PID=$(grep -o '"target_pid": [0-9]*' /tmp/task_pids.json | cut -d' ' -f2)
    SAFE_PID=$(grep -o '"safe_pid": [0-9]*' /tmp/task_pids.json | cut -d' ' -f2)
else
    echo "ERROR: PID file not found"
    TARGET_PID=""
    SAFE_PID=""
fi

# Check status
# kill -0 checks if process can be signalled (i.e., it exists)
if [ -n "$TARGET_PID" ] && kill -0 "$TARGET_PID" 2>/dev/null; then
    TARGET_RUNNING="true"
else
    TARGET_RUNNING="false"
fi

if [ -n "$SAFE_PID" ] && kill -0 "$SAFE_PID" 2>/dev/null; then
    SAFE_RUNNING="true"
else
    SAFE_RUNNING="false"
fi

# Clean up remaining processes if they survived (don't leave high CPU load)
if [ "$TARGET_RUNNING" = "true" ]; then
    kill -9 "$TARGET_PID" 2>/dev/null || true
fi
if [ "$SAFE_RUNNING" = "true" ]; then
    kill -9 "$SAFE_PID" 2>/dev/null || true
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_pid": "$TARGET_PID",
    "safe_pid": "$SAFE_PID",
    "target_running": $TARGET_RUNNING,
    "safe_running": $SAFE_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="