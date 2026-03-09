#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract Audio Result ==="

# Check for output audio file
OUTPUT_AUDIO="/home/ga/Music/lecture_audio.mp3"
SOURCE_VIDEO="/home/ga/Videos/lecture_recording.mp4"

if [ -f "$OUTPUT_AUDIO" ]; then
    echo "✅ Audio file found: $OUTPUT_AUDIO"
    cp "$OUTPUT_AUDIO" /tmp/vlc_extracted_audio.mp3
    ls -lh "$OUTPUT_AUDIO"
else
    echo "⚠️ Audio file not found at expected location"
    
    # Look for any recently created audio in Music directory
    RECENT_AUDIO=$(find /home/ga/Music -type f \( -name "*.mp3" -o -name "*.mp4" -o -name "*.m4a" \) -mmin -5 2>/dev/null | head -1)
    
    if [ -n "$RECENT_AUDIO" ]; then
        echo "Found recent audio file: $RECENT_AUDIO"
        cp "$RECENT_AUDIO" /tmp/vlc_extracted_audio.mp3
    else
        echo "❌ No audio output found"
        # Create empty file to prevent verification errors
        touch /tmp/vlc_extracted_audio.mp3
    fi
fi

# Copy source video for reference (for verification to check duration)
if [ -f "$SOURCE_VIDEO" ]; then
    cp "$SOURCE_VIDEO" /tmp/vlc_source_video.mp4
    echo "✅ Copied source video for verification"
fi

# Close VLC
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

echo "$(date)" > /tmp/vlc_extract_audio_completed.txt
echo "Extract audio task completed" >> /tmp/vlc_extract_audio_completed.txt

echo "=== Export Complete ==="