#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Auto Stop Sleep Timer Result ==="

# Record end time
END_TIMESTAMP=$(date +%s)
echo "$END_TIMESTAMP" > /tmp/vlc_end_time.txt
echo "Export called at timestamp: $END_TIMESTAMP"

# Check if VLC is still running
VLC_RUNNING="false"
if is_vlc_running; then
    VLC_RUNNING="true"
    echo "⚠️  WARNING: VLC still running at export time"
    
    # Force close VLC
    echo "Forcing VLC to close..."
    kill_vlc ga
    sleep 2
else
    echo "✅ VLC not running (expected for successful auto-stop)"
fi

# Check for start time marker
START_TIMESTAMP=""
if [ -f "/tmp/vlc_start_time.txt" ]; then
    START_TIMESTAMP=$(cat /tmp/vlc_start_time.txt)
    echo "Start timestamp found: $START_TIMESTAMP"
    
    # Calculate runtime
    if [ -n "$START_TIMESTAMP" ] && [ "$START_TIMESTAMP" -gt 0 ]; then
        RUNTIME=$((END_TIMESTAMP - START_TIMESTAMP))
        echo "Calculated runtime: ${RUNTIME} seconds"
    fi
else
    echo "⚠️  Start timestamp not found"
fi

# Check for launch command record
LAUNCH_CMD=""
if [ -f "/tmp/vlc_launch_cmd.txt" ]; then
    LAUNCH_CMD=$(cat /tmp/vlc_launch_cmd.txt)
    echo "Launch command: $LAUNCH_CMD"
fi

# Create result JSON
cat > /tmp/vlc_sleep_timer_result.json <<EOF
{
    "vlc_still_running": $VLC_RUNNING,
    "start_timestamp": "${START_TIMESTAMP:-0}",
    "end_timestamp": "$END_TIMESTAMP",
    "runtime_seconds": $((END_TIMESTAMP - ${START_TIMESTAMP:-$END_TIMESTAMP})),
    "launch_command": "$LAUNCH_CMD",
    "export_time": "$(date)"
}
EOF

echo "✅ Result saved to /tmp/vlc_sleep_timer_result.json"
cat /tmp/vlc_sleep_timer_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_sleep_timer_completed.txt
echo "VLC sleep timer task completed" >> /tmp/vlc_sleep_timer_completed.txt
echo "Runtime: $((END_TIMESTAMP - ${START_TIMESTAMP:-$END_TIMESTAMP})) seconds" >> /tmp/vlc_sleep_timer_completed.txt

echo "=== Export Complete ==="