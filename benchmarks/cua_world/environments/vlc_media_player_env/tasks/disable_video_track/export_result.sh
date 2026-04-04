#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Disable Video Track Result ==="

# Primary result: Copy VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"
RESULT_DIR="/tmp/vlc_disable_video_result"

mkdir -p "$RESULT_DIR"

if [ -f "$VLC_RC" ]; then
    echo "✅ Copying VLC configuration..."
    cp "$VLC_RC" "$RESULT_DIR/vlcrc"
    
    # Extract video-related settings for easy inspection
    echo "Video-related settings in vlcrc:" > "$RESULT_DIR/video_settings.txt"
    grep -E "^(vout|video|no-video|novideo)" "$VLC_RC" >> "$RESULT_DIR/video_settings.txt" 2>/dev/null || echo "(no video settings found)" >> "$RESULT_DIR/video_settings.txt"
    
    echo "Video settings extracted:"
    cat "$RESULT_DIR/video_settings.txt"
else
    echo "⚠️ VLC config file not found at $VLC_RC"
    echo "error: config not found" > "$RESULT_DIR/error.txt"
fi

# Secondary verification: Test playback with current settings
echo ""
echo "Testing audio-only playback capability..."

PLAYBACK_TEST_LOG="$RESULT_DIR/playback_test.log"

# Close any existing VLC instances first
if is_vlc_running; then
    echo "Closing existing VLC instance..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Test playback with cvlc (headless) to verify audio still works
echo "Running playback test (5 seconds)..."
timeout 5 su - ga -c "cvlc --play-and-exit /home/ga/Videos/lecture_long.mp4 2>&1" > "$PLAYBACK_TEST_LOG" || true

# Check if playback test shows video was disabled
if grep -q -E "(no video output|video disabled|dummy video)" "$PLAYBACK_TEST_LOG"; then
    echo "✅ Playback test confirms video disabled"
    echo "video_disabled_in_playback: true" > "$RESULT_DIR/playback_result.txt"
elif grep -q -E "(video output|vout)" "$PLAYBACK_TEST_LOG"; then
    echo "⚠️ Playback test shows video may still be active"
    echo "video_disabled_in_playback: false" > "$RESULT_DIR/playback_result.txt"
else
    echo "ℹ️ Playback test inconclusive"
    echo "video_disabled_in_playback: unknown" > "$RESULT_DIR/playback_result.txt"
fi

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    pkill -u ga vlc || true
    sleep 1
fi

# Create structured JSON result
cat > "$RESULT_DIR/result.json" <<EOF
{
    "config_file_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)",
    "task": "disable_video_track"
}
EOF

# Create completion marker
echo "$(date)" > /tmp/vlc_disable_video_completed.txt
echo "Disable video track task completed" >> /tmp/vlc_disable_video_completed.txt

echo ""
echo "✅ Export complete. Results saved to $RESULT_DIR"
echo "=== Export Complete ==="