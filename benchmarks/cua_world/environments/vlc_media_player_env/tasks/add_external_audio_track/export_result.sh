#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Add External Audio Track Result ==="

# Initialize variables
AUDIO_DELAY=""
AUDIO_DELAY_US=""
EXTERNAL_TRACK_FILE=""
AUDIO_TRACK_COUNT=""
RUNTIME_CAPTURED="false"

# Query VLC RC interface for audio settings
if is_vlc_running; then
    echo "Querying VLC RC interface for audio track info..."

    # Query audio track information
    ATRACK_OUTPUT=$(echo "atrack" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$ATRACK_OUTPUT" ]; then
        echo "Audio track info:"
        echo "$ATRACK_OUTPUT"
        
        # Count number of audio tracks (look for track numbers)
        AUDIO_TRACK_COUNT=$(echo "$ATRACK_OUTPUT" | grep -c "Track" || echo "1")
        
        if [ "$AUDIO_TRACK_COUNT" -gt 1 ]; then
            echo "✅ Multiple audio tracks detected: $AUDIO_TRACK_COUNT tracks"
            RUNTIME_CAPTURED="true"
        fi
    fi

    # Query status for audio delay information
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$STATUS_OUTPUT" ]; then
        # Try to extract audio delay if present in status
        # VLC may report audio-delay or desync in status
        AUDIO_DELAY=$(echo "$STATUS_OUTPUT" | grep -oP '(?:audio.?delay|desync).*?:\s*\K[-\d]+' | head -1 || echo "")
        
        if [ -n "$AUDIO_DELAY" ]; then
            echo "Audio delay from status: $AUDIO_DELAY"
        fi
    fi

    # Query get_audio_delay command (if available)
    DELAY_OUTPUT=$(echo "get_audio_delay" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$DELAY_OUTPUT" ]; then
        AUDIO_DELAY=$(echo "$DELAY_OUTPUT" | grep -oP '[-\d]+' | head -1 || echo "")
        if [ -n "$AUDIO_DELAY" ]; then
            echo "Audio delay from get_audio_delay: $AUDIO_DELAY"
        fi
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    {
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid" || true
        fi
        echo "Closing VLC..."
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2
    } || {
        echo "⚠️ Failed to close VLC gracefully"
        kill_vlc ga || true
    }
fi

# Wait for VLC to save settings
sleep 2

# Read VLC config file for audio delay and track info
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration file..."
    
    # Check for audio-desync (stored in microseconds)
    if grep -q "^audio-desync=" "$VLC_RC"; then
        AUDIO_DELAY_US=$(grep "^audio-desync=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Audio desync found in config: $AUDIO_DELAY_US microseconds"
        
        # Convert microseconds to milliseconds
        if [ -n "$AUDIO_DELAY_US" ] && [ "$AUDIO_DELAY_US" -ne 0 ]; then
            AUDIO_DELAY=$(echo "scale=0; $AUDIO_DELAY_US / 1000" | bc)
            echo "Audio delay: $AUDIO_DELAY ms"
        fi
    fi
    
    # Check for recently used files that might include commentary
    if grep -q "commentary" "$VLC_RC"; then
        EXTERNAL_TRACK_FILE=$(grep "commentary" "$VLC_RC" | head -1 | cut -d= -f2-)
        echo "External audio file reference found: $EXTERNAL_TRACK_FILE"
    fi
    
    # Check recent media list
    if grep -q "^file-list=" "$VLC_RC"; then
        RECENT_FILES=$(grep "^file-list=" "$VLC_RC" | cut -d= -f2)
        if echo "$RECENT_FILES" | grep -q "commentary"; then
            echo "Commentary found in recent files"
            EXTERNAL_TRACK_FILE="commentary.mp3"
        fi
    fi
    
    # Check for sub-file which VLC sometimes uses for external audio
    if grep -q "^sub-file=" "$VLC_RC" && grep "commentary" "$VLC_RC" | grep -q "sub-file"; then
        EXTERNAL_TRACK_FILE=$(grep "^sub-file=" "$VLC_RC" | cut -d= -f2 | grep "commentary" || echo "")
    fi
else
    echo "⚠️ VLC config file not found"
fi

# Check VLC media history/recent files
VLC_RECENT="/home/ga/.local/share/vlc/vlc-qt-interface.conf"
if [ -f "$VLC_RECENT" ]; then
    if grep -q "commentary" "$VLC_RECENT"; then
        echo "Commentary found in VLC recent files"
        EXTERNAL_TRACK_FILE="commentary.mp3"
    fi
fi

# Determine final audio delay value
FINAL_AUDIO_DELAY="${AUDIO_DELAY:-0}"

# Check if external track was likely loaded (heuristic)
EXTERNAL_TRACK_LOADED="false"
if [ -n "$EXTERNAL_TRACK_FILE" ] || [ "$AUDIO_TRACK_COUNT" -gt 1 ]; then
    EXTERNAL_TRACK_LOADED="true"
fi

# Write JSON result file
cat > /tmp/vlc_audio_track_result.json <<EOF
{
    "audio_delay_ms": $FINAL_AUDIO_DELAY,
    "audio_delay_us": "${AUDIO_DELAY_US:-0}",
    "external_track_file": "$EXTERNAL_TRACK_FILE",
    "audio_track_count": "${AUDIO_TRACK_COUNT:-1}",
    "external_track_loaded": $EXTERNAL_TRACK_LOADED,
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_checked": $([ -f "$VLC_RC" ] && echo "true" || echo "false")
}
EOF

echo "✅ Audio track result saved to /tmp/vlc_audio_track_result.json"
cat /tmp/vlc_audio_track_result.json

# Also copy the vlcrc for detailed analysis
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_audio_track_vlcrc_backup.txt
    echo "✅ VLC config backed up to /tmp/vlc_audio_track_vlcrc_backup.txt"
fi

echo "$(date)" > /tmp/vlc_audio_track_completed.txt
echo "External audio track task export completed" >> /tmp/vlc_audio_track_completed.txt

echo "=== Export Complete ==="