#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Select Audio Track Result ==="

# Query VLC RC interface for current audio track
AUDIO_TRACK_INDEX=""
AUDIO_TRACK_INFO=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for audio track..."

    # Query current audio track from RC interface using 'atrack' command
    # VLC RC returns: "( audio track: 1 )" or "> 1" depending on version
    RC_OUTPUT=$(echo "atrack" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Extract audio track number
        # Expected formats: "( audio track: 1 )" or "> 1" or "audio track: 1"
        AUDIO_TRACK_INDEX=$(echo "$RC_OUTPUT" | grep -oP '(?:audio track:|>)\s*\K[\d-]+' | head -1)

        if [ -n "$AUDIO_TRACK_INDEX" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured audio track from VLC RC: $AUDIO_TRACK_INDEX"
            AUDIO_TRACK_INFO="Track index $AUDIO_TRACK_INDEX"
        else
            echo "⚠️ Could not parse audio track from RC output: $RC_OUTPUT"
        fi
    else
        echo "⚠️ Could not query RC interface for audio track"
    fi

    # Also query status for additional info
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$STATUS_OUTPUT" ]; then
        # Try to find audio track info in status
        AUDIO_STATUS=$(echo "$STATUS_OUTPUT" | grep -i "audio" || echo "")
        if [ -n "$AUDIO_STATUS" ]; then
            echo "Audio status info: $AUDIO_STATUS"
        fi
    fi
fi

# Store the file that was playing
PLAYING_FILE=""
if is_vlc_running; then
    # Query what file is playing via RC
    FILE_INFO=$(echo "info" | nc -w 2 localhost 9999 2>/dev/null | grep -i "test_multi_audio" || echo "")
    if [ -n "$FILE_INFO" ]; then
        PLAYING_FILE="test_multi_audio.mkv"
        echo "✓ Confirmed playing: test_multi_audio.mkv"
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2

    # Force kill if still running
    if is_vlc_running; then
        echo "Forcing VLC to close..."
        kill_vlc ga
    fi
fi

# Fallback: Read VLC config if RC query failed
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ "$RUNTIME_CAPTURED" = "false" ] && [ -f "$VLC_RC" ]; then
    echo "Fallback to reading audio track from vlcrc..."

    if grep -q "^audio-track=" "$VLC_RC"; then
        AUDIO_TRACK_INDEX=$(grep "^audio-track=" "$VLC_RC" | cut -d= -f2 | head -1)
        AUDIO_TRACK_INFO="Track index $AUDIO_TRACK_INDEX (from config)"
        echo "Audio track from config: $AUDIO_TRACK_INDEX"
    else
        echo "No audio-track setting found in vlcrc"
    fi
fi

# If still no audio track info, set to -1 (unknown)
if [ -z "$AUDIO_TRACK_INDEX" ]; then
    AUDIO_TRACK_INDEX="-1"
    AUDIO_TRACK_INFO="Not detected"
fi

# Write JSON result file
cat > /tmp/vlc_audio_track_result.json <<EOF
{
    "audio_track_index": $AUDIO_TRACK_INDEX,
    "audio_track_info": "$AUDIO_TRACK_INFO",
    "playing_file": "$PLAYING_FILE",
    "runtime_captured": $RUNTIME_CAPTURED,
    "source": "$([ "$RUNTIME_CAPTURED" = "true" ] && echo "rc" || echo "vlcrc")"
}
EOF

echo "✅ Audio track result saved to /tmp/vlc_audio_track_result.json"
cat /tmp/vlc_audio_track_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_audio_track_completed.txt
echo "Audio track: $AUDIO_TRACK_INDEX" >> /tmp/vlc_audio_track_completed.txt
echo "Runtime captured: $RUNTIME_CAPTURED" >> /tmp/vlc_audio_track_completed.txt

echo "=== Export Complete ==="