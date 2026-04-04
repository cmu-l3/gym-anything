#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Karaoke Track Result ==="

# Define expected output location
KARAOKE_FILE="/home/ga/Music/karaoke_version.mp3"
ORIGINAL_FILE="/home/ga/Music/practice_song.mp3"

# Check if karaoke version exists
if [ -f "$KARAOKE_FILE" ]; then
    echo "✅ Karaoke version found: $KARAOKE_FILE"
    
    # Copy to standard export location
    cp "$KARAOKE_FILE" /tmp/vlc_karaoke_output.mp3
    
    # Get file info
    FILE_SIZE=$(stat -c%s "$KARAOKE_FILE" 2>/dev/null || stat -f%z "$KARAOKE_FILE" 2>/dev/null)
    echo "Karaoke file size: ${FILE_SIZE} bytes"
    
    # Get audio properties if ffprobe available
    if command -v ffprobe &> /dev/null; then
        echo "Karaoke file properties:"
        ffprobe -v error -show_entries stream=codec_name,channels,sample_rate,duration \
                -of default=noprint_wrappers=1 \
                "$KARAOKE_FILE" 2>/dev/null || echo "Could not probe audio properties"
    fi
else
    echo "⚠️ Karaoke version not found at $KARAOKE_FILE"
    
    # Look for any recently created audio files in Music directory
    echo "Searching for recently created audio files..."
    RECENT_AUDIO=$(find /home/ga/Music -name "*.mp3" -o -name "*.wav" -o -name "*.ogg" -mmin -10 2>/dev/null | grep -v "practice_song.mp3" | head -1)
    
    if [ -n "$RECENT_AUDIO" ]; then
        echo "Found recent audio file: $RECENT_AUDIO"
        cp "$RECENT_AUDIO" /tmp/vlc_karaoke_output.mp3
    else
        echo "No recent audio files found"
        # Create empty marker file
        touch /tmp/vlc_karaoke_not_created.flag
    fi
fi

# Also copy original for comparison in verification
if [ -f "$ORIGINAL_FILE" ]; then
    cp "$ORIGINAL_FILE" /tmp/vlc_karaoke_original.mp3
    echo "✅ Copied original file for comparison"
fi

# Export VLC config for inspection (might contain filter settings)
if [ -f /home/ga/.config/vlc/vlcrc ]; then
    cp /home/ga/.config/vlc/vlcrc /tmp/vlc_karaoke_config.txt
fi

# List Music directory contents
echo "Music directory contents:"
ls -lh /home/ga/Music/ > /tmp/vlc_music_dir_listing.txt 2>&1
cat /tmp/vlc_music_dir_listing.txt

# Close VLC gracefully
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
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_karaoke_completed.txt
echo "Karaoke track creation task completed" >> /tmp/vlc_karaoke_completed.txt

echo "=== Export Complete ==="