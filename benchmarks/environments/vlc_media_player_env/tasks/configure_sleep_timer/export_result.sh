#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Sleep Timer Result ==="

# Initialize result tracking
RUNTIME_CAPTURED="false"
RUNTIME_VALUE=0
QUIT_CONFIGURED="false"
VIDEO_FILE_FOUND="false"

# Capture VLC process information (command line with arguments)
echo "Capturing VLC process information..."
ps aux | grep -E "[v]lc|[c]vlc" > /tmp/vlc_process_info.txt 2>&1 || echo "No VLC process currently running" > /tmp/vlc_process_info.txt

# Check if process info contains relevant information
if grep -qE "(--run-time|--stop-time|relaxing_thunderstorm)" /tmp/vlc_process_info.txt 2>/dev/null; then
    echo "✅ Found VLC process with runtime parameters"
    RUNTIME_CAPTURED="true"
    
    # Extract runtime value
    RUNTIME_VALUE=$(grep -oP '(?:--run-time=|--stop-time=)\K\d+' /tmp/vlc_process_info.txt | head -1 || echo "0")
    echo "Runtime value from process: $RUNTIME_VALUE seconds"
    
    # Check for quit configuration
    if grep -qE "(--play-and-exit|vlc://quit)" /tmp/vlc_process_info.txt; then
        QUIT_CONFIGURED="true"
        echo "✅ Quit configuration found"
    fi
    
    # Check for video file
    if grep -q "relaxing_thunderstorm" /tmp/vlc_process_info.txt; then
        VIDEO_FILE_FOUND="true"
        echo "✅ Correct video file found in command"
    fi
fi

# Capture command history to see how VLC was launched
echo "Capturing command history..."
su - ga -c "history 100" 2>/dev/null | grep -E "vlc|cvlc" | tail -30 > /tmp/vlc_command_history.txt 2>&1 || echo "No VLC command history" > /tmp/vlc_command_history.txt

# If runtime not captured from process, try from history
if [ "$RUNTIME_CAPTURED" = "false" ] && [ -f /tmp/vlc_command_history.txt ]; then
    if grep -qE "(--run-time|--stop-time)" /tmp/vlc_command_history.txt; then
        echo "✅ Found runtime parameters in command history"
        RUNTIME_CAPTURED="true"
        RUNTIME_VALUE=$(grep -oP '(?:--run-time=|--stop-time=)\K\d+' /tmp/vlc_command_history.txt | tail -1 || echo "0")
        
        if grep -qE "(--play-and-exit|vlc://quit)" /tmp/vlc_command_history.txt; then
            QUIT_CONFIGURED="true"
        fi
        
        if grep -q "relaxing_thunderstorm" /tmp/vlc_command_history.txt; then
            VIDEO_FILE_FOUND="true"
        fi
    fi
fi

# Also check bash history file directly
echo "Checking bash history file..."
if [ -f /home/ga/.bash_history ]; then
    tail -100 /home/ga/.bash_history | grep -E "vlc|cvlc" > /tmp/bash_vlc_history.txt 2>&1 || echo "No bash VLC history" > /tmp/bash_vlc_history.txt
    
    if [ "$RUNTIME_CAPTURED" = "false" ]; then
        if grep -qE "(--run-time|--stop-time)" /tmp/bash_vlc_history.txt; then
            echo "✅ Found runtime parameters in bash history"
            RUNTIME_CAPTURED="true"
            RUNTIME_VALUE=$(grep -oP '(?:--run-time=|--stop-time=)\K\d+' /tmp/bash_vlc_history.txt | tail -1 || echo "0")
            
            if grep -qE "(--play-and-exit|vlc://quit)" /tmp/bash_vlc_history.txt; then
                QUIT_CONFIGURED="true"
            fi
            
            if grep -q "relaxing_thunderstorm" /tmp/bash_vlc_history.txt; then
                VIDEO_FILE_FOUND="true"
            fi
        fi
    fi
else
    echo "No bash history" > /tmp/bash_vlc_history.txt
fi

# Export VLC config if it exists (might have relevant settings)
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_CONFIG" ]; then
    cp "$VLC_CONFIG" /tmp/vlcrc_config.txt
    echo "✅ VLC config exported"
else
    echo "No VLC config found" > /tmp/vlcrc_config.txt
fi

# Check if VLC is currently running
echo "Checking VLC running status..."
if pgrep -a vlc > /tmp/vlc_running_status.txt 2>&1; then
    echo "VLC is currently running"
else
    echo "VLC not running" > /tmp/vlc_running_status.txt
fi

# Check for any screen or tmux sessions with VLC
screen -ls 2>/dev/null | grep vlc > /tmp/screen_sessions.txt 2>&1 || echo "No screen sessions with VLC" > /tmp/screen_sessions.txt

# Close VLC if still running (task is about configuration, not actual 45-min playback)
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" 2>/dev/null || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q 2>/dev/null || pkill -u ga vlc || true
    sleep 2
fi

# Write comprehensive JSON result file
cat > /tmp/vlc_sleep_timer_result.json <<EOF
{
    "runtime_captured": $RUNTIME_CAPTURED,
    "runtime_value": $RUNTIME_VALUE,
    "quit_configured": $QUIT_CONFIGURED,
    "video_file_found": $VIDEO_FILE_FOUND,
    "expected_runtime": 2700,
    "tolerance_min": 2400,
    "tolerance_max": 3000
}
EOF

echo "✅ Sleep timer result saved to /tmp/vlc_sleep_timer_result.json"
cat /tmp/vlc_sleep_timer_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_sleep_timer_completed.txt
echo "Runtime captured: ${RUNTIME_CAPTURED}" >> /tmp/vlc_sleep_timer_completed.txt
echo "Runtime value: ${RUNTIME_VALUE} seconds" >> /tmp/vlc_sleep_timer_completed.txt
echo "Quit configured: ${QUIT_CONFIGURED}" >> /tmp/vlc_sleep_timer_completed.txt
echo "Video file: ${VIDEO_FILE_FOUND}" >> /tmp/vlc_sleep_timer_completed.txt

echo ""
echo "=== Export Summary ==="
echo "Runtime captured: ${RUNTIME_CAPTURED}"
if [ "$RUNTIME_CAPTURED" = "true" ]; then
    echo "Runtime value: ${RUNTIME_VALUE} seconds ($(echo "scale=1; $RUNTIME_VALUE / 60" | bc) minutes)"
    echo "Quit configured: ${QUIT_CONFIGURED}"
    echo "Video file correct: ${VIDEO_FILE_FOUND}"
fi

echo "=== Export Complete ==="

exit 0