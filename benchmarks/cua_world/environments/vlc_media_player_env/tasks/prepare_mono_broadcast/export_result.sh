#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prepare Mono Broadcast Result ==="

# Expected output path
MONO_OUTPUT="/home/ga/Music/broadcast_ready/listener_recording_mono.wav"

# Check for converted mono audio file
if [ -f "$MONO_OUTPUT" ]; then
    echo "✅ Mono audio file found: $MONO_OUTPUT"
    
    # Copy to /tmp for verification
    cp "$MONO_OUTPUT" /tmp/vlc_mono_broadcast.wav
    
    # Get file info
    ls -lh "$MONO_OUTPUT"
    
    # Check channel count
    CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$MONO_OUTPUT" 2>/dev/null || echo "0")
    echo "Output channels: $CHANNELS"
    
    # Get duration
    DURATION=$(ffprobe -v error -select_streams a:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$MONO_OUTPUT" 2>/dev/null || echo "0")
    echo "Output duration: ${DURATION}s"
    
else
    echo "⚠️ Expected mono audio file not found at: $MONO_OUTPUT"
    
    # Look for any recently created audio in broadcast_ready directory
    RECENT_AUDIO=$(find /home/ga/Music/broadcast_ready -type f \( -name "*.wav" -o -name "*.mp3" -o -name "*.ogg" \) -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_AUDIO" ]; then
        echo "Found recent audio file: $RECENT_AUDIO"
        cp "$RECENT_AUDIO" /tmp/vlc_mono_broadcast.wav
    else
        echo "❌ No converted audio file found"
        # Create empty marker to indicate failure
        touch /tmp/vlc_mono_broadcast_not_found.txt
    fi
fi

# Copy original stereo file for comparison
if [ -f /home/ga/Music/submissions/listener_recording.wav ]; then
    cp /home/ga/Music/submissions/listener_recording.wav /tmp/vlc_original_stereo.wav
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

# Create completion marker
echo "$(date)" > /tmp/vlc_mono_broadcast_completed.txt
echo "Mono broadcast conversion task completed" >> /tmp/vlc_mono_broadcast_completed.txt

echo "=== Export Complete ==="