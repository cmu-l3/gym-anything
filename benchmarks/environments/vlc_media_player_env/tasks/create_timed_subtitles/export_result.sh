#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Timed Subtitles Result ==="

# Define expected subtitle file location
SUBTITLE_FILE="/home/ga/Videos/python_tutorial.srt"
EXPORT_TARGET="/tmp/vlc_created_subtitles.srt"

# Check if subtitle file was created
if [ -f "$SUBTITLE_FILE" ]; then
    echo "✅ Subtitle file found: $SUBTITLE_FILE"
    cp "$SUBTITLE_FILE" "$EXPORT_TARGET"
    
    # Show basic info about the file
    echo "File size: $(stat -f%z "$SUBTITLE_FILE" 2>/dev/null || stat -c%s "$SUBTITLE_FILE" 2>/dev/null || echo 'unknown') bytes"
    echo "First 10 lines:"
    head -n 10 "$SUBTITLE_FILE" || true
else
    echo "⚠️ Subtitle file not found at: $SUBTITLE_FILE"
    
    # Check if file exists elsewhere in Videos directory
    FOUND_SRT=$(find /home/ga/Videos -name "*.srt" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$FOUND_SRT" ]; then
        echo "Found SRT file at alternate location: $FOUND_SRT"
        cp "$FOUND_SRT" "$EXPORT_TARGET"
    else
        echo "❌ No SRT file found in /home/ga/Videos/"
        # Create empty marker file to indicate no output
        touch "$EXPORT_TARGET"
    fi
fi

# Copy source materials for reference
cp /home/ga/Videos/python_tutorial.mp4 /tmp/vlc_tutorial_video.mp4 2>/dev/null || echo "⚠️ Could not copy video"
cp /home/ga/Videos/python_script.txt /tmp/vlc_tutorial_script.txt 2>/dev/null || echo "⚠️ Could not copy script"

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
fi

# Kill any remaining VLC processes
kill_vlc ga || true

# Create completion marker
echo "$(date)" > /tmp/vlc_subtitle_create_completed.txt
echo "Subtitle creation task export completed" >> /tmp/vlc_subtitle_create_completed.txt

# Create export summary
cat > /tmp/vlc_subtitle_export_summary.txt << EOF
Create Timed Subtitles Task - Export Summary
=============================================

Timestamp: $(date)

Expected output: /home/ga/Videos/python_tutorial.srt
Exported to: /tmp/vlc_created_subtitles.srt

Files exported:
  - Subtitle file (if created)
  - Source video
  - Script text

Status: $([ -f "$SUBTITLE_FILE" ] && echo "✅ Subtitle file found" || echo "❌ Subtitle file not found")
EOF

cat /tmp/vlc_subtitle_export_summary.txt

echo "=== Export Complete ==="