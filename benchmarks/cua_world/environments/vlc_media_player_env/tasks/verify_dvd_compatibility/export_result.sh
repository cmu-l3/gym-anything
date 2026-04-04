#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify DVD Compatibility Result ==="

REPORT_FILE="/home/ga/Documents/dvd_compatibility_report.txt"
TEST_VIDEO="/home/ga/Videos/family_reunion.mp4"

# Check if report file exists and has content
if [ -f "$REPORT_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$REPORT_FILE")
    echo "✅ Report file found: $REPORT_FILE (${FILE_SIZE} bytes)"
    
    # Copy report to /tmp for verification
    cp "$REPORT_FILE" /tmp/dvd_compatibility_report.txt
    
    echo "--- Report Content Preview ---"
    head -30 "$REPORT_FILE"
    echo "--- End Preview ---"
else
    echo "⚠️ Report file not found at: $REPORT_FILE"
    
    # Look for any text file in Documents that might be the report
    RECENT_FILE=$(find /home/ga/Documents -name "*.txt" -mmin -10 -type f 2>/dev/null | head -1)
    
    if [ -n "$RECENT_FILE" ]; then
        echo "Found recent text file: $RECENT_FILE"
        cp "$RECENT_FILE" /tmp/dvd_compatibility_report.txt
    else
        # Create empty file to avoid verification errors
        echo "Report not created" > /tmp/dvd_compatibility_report.txt
    fi
fi

# Export actual video properties using ffprobe for verification
echo "Exporting actual video properties..."

if [ -f "$TEST_VIDEO" ]; then
    ffprobe -v error -show_format -show_streams \
            -of json "$TEST_VIDEO" > /tmp/actual_video_properties.json 2>&1
    
    echo "✅ Actual video properties exported"
else
    echo "⚠️ Test video not found"
    echo '{"error": "video not found"}' > /tmp/actual_video_properties.json
fi

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_dvd_compat_completed.txt
echo "DVD compatibility verification task completed" >> /tmp/vlc_dvd_compat_completed.txt

echo "=== Export Complete ==="