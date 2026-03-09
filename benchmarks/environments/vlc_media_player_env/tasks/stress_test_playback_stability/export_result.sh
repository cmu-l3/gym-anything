#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Stress Test Playback Stability Result ==="

# Check if VLC is still running (good sign - didn't crash)
VLC_RUNNING="false"
if is_vlc_running; then
    VLC_RUNNING="true"
    echo "✅ VLC still running (no crash detected)"
else
    echo "⚠️ VLC not running (may have finished or crashed)"
fi

# Copy VLC log for analysis
STABILITY_LOG="/tmp/vlc_stability_log.txt"
if [ -f /tmp/vlc_stability_test.log ]; then
    cp /tmp/vlc_stability_test.log "$STABILITY_LOG"
    echo "✅ VLC log captured: $(wc -l < $STABILITY_LOG) lines"
    
    # Check log for crash indicators
    CRASH_COUNT=0
    for indicator in "segmentation fault" "core dumped" "fatal" "crashed" "killed" "signal 11"; do
        if grep -qi "$indicator" "$STABILITY_LOG"; then
            CRASH_COUNT=$((CRASH_COUNT + 1))
            echo "⚠️ Found potential crash indicator: $indicator"
        fi
    done
    
    if [ $CRASH_COUNT -eq 0 ]; then
        echo "✅ No crash indicators found in log"
    fi
else
    echo "⚠️ VLC log not found at expected location"
    # Create empty log as fallback
    touch "$STABILITY_LOG"
fi

# Check for user-created result report
RESULT_FILE="/home/ga/Videos/stress_test_result.txt"
USER_CREATED_REPORT="false"

if [ -f "$RESULT_FILE" ]; then
    echo "✅ User created result report found"
    USER_CREATED_REPORT="true"
    cat "$RESULT_FILE"
else
    echo "⚠️ User did not create result report"
fi

# Close VLC gracefully if still running
if [ "$VLC_RUNNING" = "true" ]; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create comprehensive result JSON
cat > /tmp/vlc_stability_result.json <<EOF
{
    "vlc_running_at_export": $VLC_RUNNING,
    "log_size_lines": $(wc -l < "$STABILITY_LOG" 2>/dev/null || echo "0"),
    "crash_indicators_found": $CRASH_COUNT,
    "user_created_report": $USER_CREATED_REPORT,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Stability result saved to /tmp/vlc_stability_result.json"
cat /tmp/vlc_stability_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_stress_test_completed.txt
echo "Stress test completed" >> /tmp/vlc_stress_test_completed.txt
echo "VLC was running at export: $VLC_RUNNING" >> /tmp/vlc_stress_test_completed.txt
echo "Crash indicators found: $CRASH_COUNT" >> /tmp/vlc_stress_test_completed.txt

echo "=== Export Complete ==="