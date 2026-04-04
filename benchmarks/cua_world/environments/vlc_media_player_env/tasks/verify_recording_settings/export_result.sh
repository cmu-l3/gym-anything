#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Recording Settings Result ==="

# Check if verification report exists
REPORT_FILE="/home/ga/Documents/recording_verification.txt"

if [ -f "$REPORT_FILE" ]; then
    echo "✅ Verification report found: $REPORT_FILE"
    cp "$REPORT_FILE" /tmp/recording_verification.txt
    echo "--- Report Contents ---"
    cat "$REPORT_FILE"
    echo "--- End Report ---"
else
    echo "⚠️ Verification report not found at expected location"
    
    # Search for any recent text files in Documents that might be the report
    RECENT_TXT=$(find /home/ga/Documents -name "*.txt" -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_TXT" ]; then
        echo "Found recent text file: $RECENT_TXT"
        cp "$RECENT_TXT" /tmp/recording_verification.txt
        echo "--- File Contents ---"
        cat "$RECENT_TXT"
        echo "--- End File ---"
    else
        echo "No report file found, creating empty marker"
        touch /tmp/recording_verification_missing.marker
    fi
fi

# Extract actual video specs for verifier cross-check
VIDEO_FILE="/home/ga/Videos/camera_test.mp4"

if [ -f "$VIDEO_FILE" ]; then
    echo "Extracting actual video specifications for verification..."
    
    # Get detailed video information as JSON
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,r_frame_rate,codec_name,bit_rate,codec_long_name \
        -show_entries format=duration,size,bit_rate \
        -of json \
        "$VIDEO_FILE" > /tmp/actual_video_specs.json 2>&1
    
    echo "✅ Video specs extracted to /tmp/actual_video_specs.json"
    
    # Also create human-readable version for debugging
    echo "--- Actual Video Specs ---"
    cat /tmp/actual_video_specs.json
    echo "--- End Specs ---"
else
    echo "⚠️ Source video not found: $VIDEO_FILE"
fi

# Check if VLC config has any relevant settings (though this task doesn't require config changes)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_config_snapshot.txt || true
fi

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# If VLC still running, force kill
if is_vlc_running; then
    echo "Force killing VLC..."
    kill_vlc ga
fi

# Create completion marker
echo "$(date)" > /tmp/verify_settings_completed.txt
echo "Verification task completed" >> /tmp/verify_settings_completed.txt

# List all exported files for debugging
echo "Exported files:"
ls -lah /tmp/recording_verification* /tmp/actual_video_specs.json /tmp/verify_settings_completed.txt 2>/dev/null || true

echo "=== Export Complete ==="