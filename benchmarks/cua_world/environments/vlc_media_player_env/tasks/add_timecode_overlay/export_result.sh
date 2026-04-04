#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Add Timecode Overlay Result ==="

# Initialize result variables
TIMECODE_ENABLED="false"
TIMECODE_SETTINGS="{}"
RUNTIME_CAPTURED="false"
SCREENSHOT_FOUND="false"

# Query VLC RC interface for current filter settings
if is_vlc_running; then
    echo "Querying VLC RC interface for filter status..."
    
    # Query status which includes filter information
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_OUTPUT" ]; then
        echo "RC output received, checking for time overlay..."
        
        # Check if time overlay is mentioned in status
        if echo "$RC_OUTPUT" | grep -qi "time"; then
            TIMECODE_ENABLED="true"
            RUNTIME_CAPTURED="true"
            echo "✅ Time overlay detected in RC status"
        fi
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Primary verification: Read VLC config file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading timecode settings from vlcrc..."
    
    # Check for time-overlay setting
    if grep -q "^time-overlay=1" "$VLC_RC"; then
        TIMECODE_ENABLED="true"
        echo "✅ Time overlay enabled in config"
    fi
    
    # Check for alternative: sub-source with marq (marquee) that shows time
    if grep -q "^sub-source=marq" "$VLC_RC" && grep -q "time" "$VLC_RC"; then
        TIMECODE_ENABLED="true"
        echo "✅ Marquee time display enabled in config"
    fi
    
    # Check for video-filter or vout-filter containing time
    if grep -E "^(video-filter|vout-filter)=.*time" "$VLC_RC"; then
        TIMECODE_ENABLED="true"
        echo "✅ Time filter found in video filter chain"
    fi
    
    # Extract all timecode-related settings
    SETTINGS_JSON=""
    
    for setting in time-overlay time-position time-opacity time-color marq-marquee sub-source video-filter vout-filter; do
        if grep -q "^${setting}=" "$VLC_RC"; then
            VALUE=$(grep "^${setting}=" "$VLC_RC" | cut -d= -f2 | head -1 | sed 's/"/\\"/g')
            [ -n "$SETTINGS_JSON" ] && SETTINGS_JSON="${SETTINGS_JSON},"
            SETTINGS_JSON="${SETTINGS_JSON}\"${setting}\": \"${VALUE}\""
        fi
    done
    
    if [ -n "$SETTINGS_JSON" ]; then
        TIMECODE_SETTINGS="{${SETTINGS_JSON}}"
        echo "Found timecode settings: $TIMECODE_SETTINGS"
    fi
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Check for screenshot (optional verification evidence)
SNAPSHOT_DIR="/home/ga/Pictures/vlc"
LATEST_SNAPSHOT=$(find "$SNAPSHOT_DIR" -name "vlc-snap*" -mmin -5 2>/dev/null | head -1)

if [ -n "$LATEST_SNAPSHOT" ] && [ -f "$LATEST_SNAPSHOT" ]; then
    echo "✅ Screenshot found: $LATEST_SNAPSHOT"
    cp "$LATEST_SNAPSHOT" /tmp/vlc_timecode_screenshot.png
    SCREENSHOT_FOUND="true"
else
    echo "⚠️ No recent screenshot found (optional)"
fi

# Check for output video (bonus - if user tried to export with burned-in timecode)
OUTPUT_VIDEO="/home/ga/Videos/timecode_output/student_film_with_timecode.mp4"
OUTPUT_EXISTS="false"

if [ -f "$OUTPUT_VIDEO" ]; then
    echo "✅ Output video found: $OUTPUT_VIDEO"
    cp "$OUTPUT_VIDEO" /tmp/vlc_timecode_output.mp4
    OUTPUT_EXISTS="true"
fi

# Write JSON result file
cat > /tmp/vlc_timecode_result.json <<EOF
{
    "timecode_enabled": $TIMECODE_ENABLED,
    "timecode_settings": $TIMECODE_SETTINGS,
    "runtime_captured": $RUNTIME_CAPTURED,
    "screenshot_found": $SCREENSHOT_FOUND,
    "output_video_exists": $OUTPUT_EXISTS,
    "config_file_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false")
}
EOF

echo "✅ Timecode result saved to /tmp/vlc_timecode_result.json"
cat /tmp/vlc_timecode_result.json

echo "$(date)" > /tmp/vlc_timecode_completed.txt
echo "Timecode overlay task completed" >> /tmp/vlc_timecode_completed.txt
echo "Timecode enabled: ${TIMECODE_ENABLED}" >> /tmp/vlc_timecode_completed.txt

echo "=== Export Complete ==="