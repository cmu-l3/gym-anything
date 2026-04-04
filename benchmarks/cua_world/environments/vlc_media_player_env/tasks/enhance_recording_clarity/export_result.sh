#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Enhance Recording Clarity Result ==="

USER_HOME="/home/ga"
MUSIC_DIR="$USER_HOME/Music"
ENHANCED_FILE="$MUSIC_DIR/enhanced_recording.mp3"
ORIGINAL_FILE="$MUSIC_DIR/noisy_recording.mp3"

# Check if enhanced audio exists
if [ -f "$ENHANCED_FILE" ]; then
    echo "✅ Enhanced recording found: $ENHANCED_FILE"
    cp "$ENHANCED_FILE" /tmp/vlc_enhanced_audio.mp3
    ls -lh "$ENHANCED_FILE"
    
    # Generate audio analysis for enhanced file
    ffprobe -v error -show_entries format=duration,bit_rate,size \
      -show_entries stream=codec_name,sample_rate,channels \
      "$ENHANCED_FILE" > /tmp/enhanced_audio_info.txt 2>&1 || true
    
    # Calculate volume levels
    echo "Analyzing volume levels..."
    ffmpeg -i "$ENHANCED_FILE" -af "volumedetect" -f null - 2>&1 | \
      grep "mean_volume\|max_volume" > /tmp/enhanced_volume.txt || echo "mean_volume: -30.0 dB" > /tmp/enhanced_volume.txt
    
else
    echo "⚠️ Enhanced recording not found at expected location: $ENHANCED_FILE"
    
    # Look for any recently created audio file in Music directory
    RECENT_AUDIO=$(find "$MUSIC_DIR" -type f \( -name "*.mp3" -o -name "*.wav" \) -mmin -10 ! -name "noisy_recording.mp3" 2>/dev/null | head -1)
    
    if [ -n "$RECENT_AUDIO" ]; then
        echo "Found recent audio file: $RECENT_AUDIO"
        cp "$RECENT_AUDIO" /tmp/vlc_enhanced_audio.mp3
        
        ffprobe -v error -show_entries format=duration,bit_rate,size \
          -show_entries stream=codec_name,sample_rate,channels \
          "$RECENT_AUDIO" > /tmp/enhanced_audio_info.txt 2>&1 || true
        
        ffmpeg -i "$RECENT_AUDIO" -af "volumedetect" -f null - 2>&1 | \
          grep "mean_volume\|max_volume" > /tmp/enhanced_volume.txt || echo "mean_volume: -30.0 dB" > /tmp/enhanced_volume.txt
    else
        touch /tmp/ENHANCEMENT_NOT_FOUND.txt
    fi
fi

# Always copy original for comparison
if [ -f "$ORIGINAL_FILE" ]; then
    cp "$ORIGINAL_FILE" /tmp/vlc_original_audio.mp3
    
    ffmpeg -i "$ORIGINAL_FILE" -af "volumedetect" -f null - 2>&1 | \
      grep "mean_volume\|max_volume" > /tmp/original_volume.txt || echo "mean_volume: -30.0 dB" > /tmp/original_volume.txt
fi

# Copy VLC config for verification of applied effects
if [ -f "$USER_HOME/.config/vlc/vlcrc" ]; then
    cp "$USER_HOME/.config/vlc/vlcrc" /tmp/vlc_enhance_config.txt || true
fi

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

echo "$(date)" > /tmp/vlc_enhance_completed.txt
echo "Audio enhancement task completed" >> /tmp/vlc_enhance_completed.txt

echo "=== Export Complete ==="
ls -lh /tmp/vlc_*audio* /tmp/*_volume.txt 2>/dev/null || true