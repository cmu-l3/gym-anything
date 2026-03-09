#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Remove Audio Noise Result ==="

# Check for cleaned audio file at expected location
CLEANED_AUDIO="/home/ga/Music/cleaned_meeting.mp3"
FOUND_CLEANED="false"

if [ -f "$CLEANED_AUDIO" ]; then
    echo "✅ Cleaned audio found at expected location: $CLEANED_AUDIO"
    FOUND_CLEANED="true"
    cp "$CLEANED_AUDIO" /tmp/vlc_cleaned_audio.mp3
    ls -lh "$CLEANED_AUDIO"
else
    echo "⚠️ Cleaned audio not found at expected location: $CLEANED_AUDIO"
    
    # Look for any recently created/modified MP3 files in Music directory
    echo "Searching for recent audio files in /home/ga/Music/..."
    RECENT_AUDIO=$(find /home/ga/Music -name "*.mp3" -type f -mmin -10 ! -name "historical_meeting.mp3" 2>/dev/null | head -1)
    
    if [ -n "$RECENT_AUDIO" ]; then
        echo "Found recent audio file: $RECENT_AUDIO"
        cp "$RECENT_AUDIO" /tmp/vlc_cleaned_audio.mp3
        FOUND_CLEANED="true"
    fi
    
    # Also check Videos directory (VLC sometimes records there)
    if [ "$FOUND_CLEANED" = "false" ]; then
        echo "Checking /home/ga/Videos/ for recorded audio..."
        RECENT_VIDEO_AUDIO=$(find /home/ga/Videos -name "*.mp3" -o -name "*.wav" -type f -mmin -10 2>/dev/null | head -1)
        
        if [ -n "$RECENT_VIDEO_AUDIO" ]; then
            echo "Found audio in Videos: $RECENT_VIDEO_AUDIO"
            cp "$RECENT_VIDEO_AUDIO" /tmp/vlc_cleaned_audio.mp3
            FOUND_CLEANED="true"
        fi
    fi
fi

# If cleaned audio was found, extract its info
if [ "$FOUND_CLEANED" = "true" ] && [ -f /tmp/vlc_cleaned_audio.mp3 ]; then
    echo "Extracting cleaned audio information..."
    ffprobe -v error -show_entries format=duration,bit_rate,size \
        -show_entries stream=codec_name,sample_rate,channels \
        -of json /tmp/vlc_cleaned_audio.mp3 \
        > /tmp/cleaned_audio_info.json 2>&1 || echo "Failed to probe cleaned audio"
    
    if [ -f /tmp/cleaned_audio_info.json ]; then
        echo "✅ Cleaned audio info extracted"
        cat /tmp/cleaned_audio_info.json
    fi
else
    echo "⚠️ No cleaned audio file found to analyze"
fi

# Copy VLC config to check if filters were configured
if [ -f "/home/ga/.config/vlc/vlcrc" ]; then
    echo "Copying VLC config..."
    cp /home/ga/.config/vlc/vlcrc /tmp/vlc_config.txt
fi

# Copy original audio info for comparison
if [ -f /tmp/original_audio_info.json ]; then
    cp /tmp/original_audio_info.json /tmp/original_audio_info_export.json
fi

# Copy VLC logs if available
if [ -f /tmp/vlc_noise_task.log ]; then
    cp /tmp/vlc_noise_task.log /tmp/vlc_noise_task_export.log
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
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_noise_completed.txt
echo "Cleaned audio found: $FOUND_CLEANED" >> /tmp/vlc_noise_completed.txt

echo "=== Export Complete ==="
echo "Cleaned audio found: $FOUND_CLEANED"