#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Media Specifications Result ==="

# Check for verification document at expected location
VERIFICATION_FILE="/home/ga/Documents/video_specs_verified.txt"
FOUND_FILE=""

if [ -f "$VERIFICATION_FILE" ]; then
    echo "✅ Verification file found at expected location: $VERIFICATION_FILE"
    FOUND_FILE="$VERIFICATION_FILE"
else
    echo "⚠️ Verification file not found at expected location"
    
    # Look for any recently created text files in Documents directory
    RECENT_FILE=$(find /home/ga/Documents -name "*.txt" -type f -mmin -10 ! -name "video_specs_template.txt" 2>/dev/null | head -1)
    
    if [ -n "$RECENT_FILE" ]; then
        echo "Found recent verification file: $RECENT_FILE"
        FOUND_FILE="$RECENT_FILE"
    else
        echo "❌ No verification file found"
    fi
fi

# Copy verification file to /tmp for verification
if [ -n "$FOUND_FILE" ]; then
    cp "$FOUND_FILE" /tmp/vlc_verification_document.txt
    echo "Verification document content:"
    echo "----------------------------------------"
    cat "$FOUND_FILE"
    echo "----------------------------------------"
else
    echo "No verification document to export"
    # Create empty file so verifier can detect absence
    touch /tmp/vlc_verification_document.txt
fi

# Also copy the actual video specs for reference
if [ -f "/home/ga/Videos/submission/contributor_video.mp4" ]; then
    ffprobe -v error -show_format -show_streams \
        /home/ga/Videos/submission/contributor_video.mp4 \
        > /tmp/vlc_actual_video_specs.txt 2>&1 || true
fi

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Kill any remaining VLC processes
kill_vlc ga || true

# Create completion marker
echo "$(date)" > /tmp/vlc_mediainfo_completed.txt
echo "Media specification verification task completed" >> /tmp/vlc_mediainfo_completed.txt

echo "=== Export Complete ==="