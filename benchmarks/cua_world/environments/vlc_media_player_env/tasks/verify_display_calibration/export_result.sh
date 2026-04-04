#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Display Calibration Result ==="

# Query VLC RC interface for current filter/adjustment state (if running)
RUNTIME_FILTERS=""
RUNTIME_ADJUSTMENTS=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for current state..."
    
    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract filter/adjustment info from status
        # Note: RC interface may not expose all settings, so we rely mainly on config file
        echo "RC status captured (limited info available via RC)"
        RUNTIME_CAPTURED="true"
    fi
fi

# Close VLC to ensure config is written to disk
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to flush configuration..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Additional attempt to close VLC if still running
if is_vlc_running; then
    echo "VLC still running, force closing..."
    kill_vlc ga
    sleep 1
fi

# Copy VLC configuration file for verification
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_CONFIG" ]; then
    cp "$VLC_CONFIG" /tmp/vlc_calibration_config.txt
    echo "✅ VLC config file copied for verification"
    
    # Extract relevant settings for logging
    echo ""
    echo "Current VLC video settings:"
    grep -E "^(video-filter|vout-filter|brightness|contrast|gamma|saturation|hue)=" "$VLC_CONFIG" || echo "  (no relevant settings found)"
else
    echo "⚠️ VLC config file not found: $VLC_CONFIG"
fi

# Check if test video was accessed recently (indicates it was played)
TEST_VIDEO="/home/ga/Videos/test_patterns/smpte_colorbars_1080p.mp4"
VIDEO_PLAYED="false"

if [ -f "$TEST_VIDEO" ]; then
    # Get file access time
    ACCESS_TIME=$(stat -c %X "$TEST_VIDEO" 2>/dev/null || echo "0")
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - ACCESS_TIME))
    
    # If accessed within last 5 minutes (300 seconds)
    if [ "$TIME_DIFF" -lt 300 ]; then
        VIDEO_PLAYED="true"
        echo "✅ Test video was accessed recently (${TIME_DIFF}s ago)"
    else
        echo "⚠️ Test video not accessed recently (${TIME_DIFF}s ago)"
    fi
else
    echo "⚠️ Test video not found"
fi

# Check VLC media library for playback history
VLC_ML="/home/ga/.local/share/vlc/ml.xspf"
ML_FOUND="false"

if [ -f "$VLC_ML" ]; then
    if grep -q "smpte_colorbars\|test_patterns" "$VLC_ML" 2>/dev/null; then
        ML_FOUND="true"
        echo "✅ Test pattern found in VLC media library"
    fi
fi

# Create JSON result file with all collected information
cat > /tmp/vlc_calibration_result.json <<EOF
{
    "config_file_exists": $([ -f "$VLC_CONFIG" ] && echo "true" || echo "false"),
    "video_played": $VIDEO_PLAYED,
    "media_library_found": $ML_FOUND,
    "runtime_captured": $RUNTIME_CAPTURED,
    "test_video_path": "$TEST_VIDEO"
}
EOF

echo "✅ Calibration result saved to /tmp/vlc_calibration_result.json"
cat /tmp/vlc_calibration_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_calibration_completed.txt
echo "Display calibration task completed" >> /tmp/vlc_calibration_completed.txt

echo ""
echo "=== Export Complete ==="