#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract Audio Result ==="

# Expected output file
OUTPUT_FILE="/home/ga/Music/extracted/practice_audio.mp3"
TEMP_OUTPUT="/tmp/vlc_extracted_audio.mp3"

# Check if output file exists at expected location
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Extracted audio found: $OUTPUT_FILE"
    
    # Get file info
    FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    echo "File size: $((FILE_SIZE / 1024)) KB"
    
    # Copy to temp location for verification
    cp "$OUTPUT_FILE" "$TEMP_OUTPUT"
    
else
    echo "⚠️ Expected output file not found at: $OUTPUT_FILE"
    
    # Search for any recently created MP3 files in the directory
    if [ -d "/home/ga/Music/extracted" ]; then
        RECENT_MP3=$(find /home/ga/Music/extracted -name "*.mp3" -type f -mmin -10 2>/dev/null | head -1)
        
        if [ -n "$RECENT_MP3" ]; then
            echo "Found recent MP3 file: $RECENT_MP3"
            cp "$RECENT_MP3" "$TEMP_OUTPUT"
        else
            echo "No MP3 files found in /home/ga/Music/extracted/"
        fi
    fi
    
    # Also check user's home directory for misplaced output
    RECENT_HOME_MP3=$(find /home/ga -maxdepth 3 -name "*.mp3" -type f -mmin -10 2>/dev/null | grep -v "/home/ga/Music/sample" | head -1)
    
    if [ -n "$RECENT_HOME_MP3" ] && [ ! -f "$TEMP_OUTPUT" ]; then
        echo "Found MP3 in home directory: $RECENT_HOME_MP3"
        cp "$RECENT_HOME_MP3" "$TEMP_OUTPUT"
    fi
fi

# Check if VLC is still running (conversion might still be in progress)
if is_vlc_running; then
    echo "VLC still running..."
    
    # Check if conversion is in progress by looking for .part files
    PART_FILE=$(find /home/ga/Music/extracted -name "*.part" -type f 2>/dev/null | head -1)
    
    if [ -n "$PART_FILE" ]; then
        echo "⚠️ Conversion appears to be in progress (found .part file)"
        echo "Waiting additional 10 seconds for completion..."
        sleep 10
        
        # Check again after waiting
        if [ -f "$OUTPUT_FILE" ]; then
            echo "✅ Conversion completed during wait"
            cp "$OUTPUT_FILE" "$TEMP_OUTPUT"
        fi
    fi
    
    # Close VLC gracefully
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_extract_audio_completed.txt
echo "Extract audio task export completed" >> /tmp/vlc_extract_audio_completed.txt

# Store source video info for verification
SOURCE_VIDEO="/home/ga/Videos/band_practice.mp4"
if [ -f "$SOURCE_VIDEO" ]; then
    SOURCE_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO" 2>/dev/null || echo "0")
    echo "source_duration=$SOURCE_DURATION" >> /tmp/vlc_extract_audio_completed.txt
fi

echo "=== Export Complete ==="