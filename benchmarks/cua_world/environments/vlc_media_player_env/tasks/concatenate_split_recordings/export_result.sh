#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Concatenate Split Recordings Result ==="

# Wait a moment for any ongoing conversion to finish
sleep 3

# Primary expected location
OUTPUT_FILE="/home/ga/Videos/complete_recording.mp4"
FOUND_OUTPUT=""

if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Concatenated video found at expected location: $OUTPUT_FILE"
    FOUND_OUTPUT="$OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Output not found at expected location: $OUTPUT_FILE"
    
    # Search for recently created video files in Videos directory
    echo "Searching for recent video files..."
    RECENT_VIDEO=$(find /home/ga/Videos -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -5 -size +100k 2>/dev/null | grep -v "split_recording" | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        FOUND_OUTPUT="$RECENT_VIDEO"
        ls -lh "$RECENT_VIDEO"
    else
        echo "❌ No recent video files found"
    fi
fi

# Copy output to temp location for verification
if [ -n "$FOUND_OUTPUT" ]; then
    cp "$FOUND_OUTPUT" /tmp/vlc_concatenated_output.mp4
    echo "✅ Output copied to /tmp/vlc_concatenated_output.mp4"
    
    # Get basic info using ffprobe
    echo "Video information:"
    ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of json "$FOUND_OUTPUT" 2>/dev/null || true
else
    echo "⚠️ No output file to copy"
    # Create empty marker to indicate no output
    touch /tmp/vlc_concatenated_output_missing.txt
fi

# Copy source files for verification comparison
mkdir -p /tmp/vlc_concat_sources
for i in 1 2 3; do
    PART_FILE="/home/ga/Videos/split_recording/recording_part${i}.mp4"
    if [ -f "$PART_FILE" ]; then
        cp "$PART_FILE" "/tmp/vlc_concat_sources/recording_part${i}.mp4"
    fi
done

# Close VLC (may still be running if conversion was ongoing)
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
        echo "Force killing VLC..."
        kill_vlc ga || true
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_concat_completed.txt
echo "Concatenate task export completed" >> /tmp/vlc_concat_completed.txt
if [ -n "$FOUND_OUTPUT" ]; then
    echo "Output file: $FOUND_OUTPUT" >> /tmp/vlc_concat_completed.txt
else
    echo "Output file: NOT FOUND" >> /tmp/vlc_concat_completed.txt
fi

echo "=== Export Complete ==="