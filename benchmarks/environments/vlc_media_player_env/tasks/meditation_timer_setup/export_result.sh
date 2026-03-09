#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Meditation Timer Result ==="

RESULT_FILE="/tmp/vlc_meditation_timer_result.json"
VIDEO_PATH="/home/ga/Videos/nature_meditation.mp4"

# Initialize result variables
TIMER_CONFIGURED="false"
TIMER_VALUE=""
TIMER_SOURCE="none"
CONFIG_METHOD=""

# Check 1: Look for timer in bash history
echo "Checking bash history for timer commands..."

HISTORY_FILE="/home/ga/.bash_history"

if [ -f "$HISTORY_FILE" ]; then
    # Look for --run-time=1800 or --run-time 1800
    if grep -qE '(--run-time=1800|--run-time 1800)' "$HISTORY_FILE"; then
        TIMER_CONFIGURED="true"
        TIMER_VALUE="1800"
        TIMER_SOURCE="bash_history"
        CONFIG_METHOD="run-time"
        echo "✅ Found --run-time=1800 in bash history"
    fi
    
    # Look for --stop-time=1800
    if grep -qE '(--stop-time=1800|--stop-time 1800)' "$HISTORY_FILE"; then
        TIMER_CONFIGURED="true"
        TIMER_VALUE="1800"
        TIMER_SOURCE="bash_history"
        CONFIG_METHOD="stop-time"
        echo "✅ Found --stop-time=1800 in bash history"
    fi
    
    # Copy history for verification
    cp "$HISTORY_FILE" /tmp/vlc_bash_history.txt 2>/dev/null || true
fi

# Check 2: Look for timer in VLC config
echo "Checking VLC config for timer settings..."

VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    if grep -qE '^run-time=1800' "$VLC_RC"; then
        TIMER_CONFIGURED="true"
        TIMER_VALUE="1800"
        TIMER_SOURCE="vlcrc"
        CONFIG_METHOD="run-time"
        echo "✅ Found run-time=1800 in VLC config"
    fi
    
    if grep -qE '^stop-time=1800' "$VLC_RC"; then
        TIMER_CONFIGURED="true"
        TIMER_VALUE="1800"
        TIMER_SOURCE="vlcrc"
        CONFIG_METHOD="stop-time"
        echo "✅ Found stop-time=1800 in VLC config"
    fi
    
    # Copy config for verification
    cp "$VLC_RC" /tmp/vlc_config.txt 2>/dev/null || true
fi

# Check 3: Look for any recent VLC process with timer arguments
echo "Checking recent VLC processes..."

RECENT_VLC_CMD=$(ps aux | grep -E 'vlc.*--(run-time|stop-time).*1800' | grep -v grep | head -1 || true)

if [ -n "$RECENT_VLC_CMD" ]; then
    TIMER_CONFIGURED="true"
    TIMER_VALUE="1800"
    TIMER_SOURCE="process"
    echo "✅ Found VLC process with timer configured"
    echo "$RECENT_VLC_CMD" > /tmp/vlc_process_info.txt
fi

# Close any running VLC instances
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Practical test: Launch VLC with short timer to verify functionality
echo "Running practical timer test (10 seconds)..."

PRACTICAL_TEST_PASSED="false"
TEST_OUTPUT=""

# Kill any lingering VLC processes
pkill -9 vlc 2>/dev/null || true
sleep 1

# Run a 10-second timer test
TEST_START=$(date +%s)
su - ga -c "DISPLAY=:1 timeout 15 vlc --run-time=10 --play-and-exit '$VIDEO_PATH' >/dev/null 2>&1 &"
VLC_PID=$!

# Wait and check if VLC terminates
sleep 11

if ! ps -p $VLC_PID > /dev/null 2>&1; then
    TEST_END=$(date +%s)
    TEST_DURATION=$((TEST_END - TEST_START))
    
    if [ $TEST_DURATION -ge 10 ] && [ $TEST_DURATION -le 13 ]; then
        PRACTICAL_TEST_PASSED="true"
        TEST_OUTPUT="VLC auto-quit after ${TEST_DURATION}s (expected ~10s)"
        echo "✅ Practical test passed: $TEST_OUTPUT"
    else
        TEST_OUTPUT="VLC quit but timing was off (${TEST_DURATION}s)"
        echo "⚠️ $TEST_OUTPUT"
    fi
else
    # VLC still running, kill it
    kill -9 $VLC_PID 2>/dev/null || true
    TEST_OUTPUT="VLC did not auto-quit after timer expired"
    echo "❌ $TEST_OUTPUT"
fi

# Clean up any remaining VLC processes
pkill -9 vlc 2>/dev/null || true

# Write JSON result file
cat > "$RESULT_FILE" <<EOF
{
    "timer_configured": $TIMER_CONFIGURED,
    "timer_value": "$TIMER_VALUE",
    "timer_source": "$TIMER_SOURCE",
    "config_method": "$CONFIG_METHOD",
    "practical_test_passed": $PRACTICAL_TEST_PASSED,
    "test_output": "$TEST_OUTPUT",
    "video_path": "$VIDEO_PATH"
}
EOF

echo "✅ Result saved to $RESULT_FILE"
cat "$RESULT_FILE"

# Create completion marker
echo "$(date)" > /tmp/vlc_meditation_timer_completed.txt
echo "Timer configured: $TIMER_CONFIGURED" >> /tmp/vlc_meditation_timer_completed.txt
echo "Practical test: $PRACTICAL_TEST_PASSED" >> /tmp/vlc_meditation_timer_completed.txt

echo "=== Export Complete ==="