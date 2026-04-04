#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Switch Audio Track Result ==="

# Initialize result variables
AUDIO_TRACK=""
AUDIO_TRACK_ID=""
TRACK_SWITCHED="false"
RUNTIME_CAPTURED="false"
VERIFICATION_METHOD="none"

# Query VLC RC interface for current audio track
if is_vlc_running; then
    echo "Querying VLC RC interface for audio track..."

    # Try 'atrack' command to get current audio track
    # VLC RC returns: "> 1" or "( audio track: 1 )" depending on version
    RC_OUTPUT=$(echo "atrack" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        echo "RC Output: $RC_OUTPUT"
        
        # Extract audio track number from various possible formats
        # Format 1: "> 1" or "> 0"
        # Format 2: "( audio track: 1 )"
        AUDIO_TRACK=$(echo "$RC_OUTPUT" | grep -oP '(?:audio track:|>)\s*\K[-\d]+' | head -1 || echo "")

        if [ -n "$AUDIO_TRACK" ]; then
            RUNTIME_CAPTURED="true"
            VERIFICATION_METHOD="rc_atrack"
            echo "✅ Captured audio track from VLC RC (atrack): $AUDIO_TRACK"
            
            # Check if track was switched (Track 1 or higher indicates Japanese/Track 2)
            # VLC may use 0-indexing (0=Track1, 1=Track2) or 1-indexing (1=Track1, 2=Track2)
            if [ "$AUDIO_TRACK" -ge 1 ] 2>/dev/null; then
                TRACK_SWITCHED="true"
                echo "✅ Track appears to be switched (value: $AUDIO_TRACK >= 1)"
            else
                echo "⚠️ Track still at default (value: $AUDIO_TRACK)"
            fi
        else
            echo "⚠️ Could not parse audio track from RC output"
        fi
    else
        echo "⚠️ Could not query RC interface (atrack)"
    fi

    # Also try 'status' command as fallback
    if [ "$RUNTIME_CAPTURED" = "false" ]; then
        echo "Trying 'status' command..."
        STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
        
        if [ -n "$STATUS_OUTPUT" ]; then
            # Try to extract audio track info from status
            AUDIO_INFO=$(echo "$STATUS_OUTPUT" | grep -i "audio" || echo "")
            if [ -n "$AUDIO_INFO" ]; then
                echo "Audio info from status: $AUDIO_INFO"
                RUNTIME_CAPTURED="true"
                VERIFICATION_METHOD="rc_status"
            fi
        fi
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    echo "Closing VLC..."
    # Try RC quit first
    echo "quit" | nc -w 1 localhost 9999 2>/dev/null || true
    sleep 1
    
    # Fallback to keyboard shortcut
    if is_vlc_running; then
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2
    fi
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Fallback: Read VLC config if RC query failed or for additional verification
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC config for additional verification..."
    
    # Look for audio-track settings
    if grep -q "^audio-track=" "$VLC_RC"; then
        AUDIO_TRACK_CFG=$(grep "^audio-track=" "$VLC_RC" | cut -d= -f2 | head -1 | tr -d ' ')
        echo "Config audio-track: $AUDIO_TRACK_CFG"
        
        # If we didn't get runtime capture, use config value
        if [ "$RUNTIME_CAPTURED" = "false" ] && [ -n "$AUDIO_TRACK_CFG" ]; then
            AUDIO_TRACK="$AUDIO_TRACK_CFG"
            VERIFICATION_METHOD="vlcrc_audio_track"
            
            # Check if switched
            if [ "$AUDIO_TRACK_CFG" -ge 1 ] 2>/dev/null; then
                TRACK_SWITCHED="true"
            fi
        fi
    fi
    
    if grep -q "^audio-track-id=" "$VLC_RC"; then
        AUDIO_TRACK_ID=$(grep "^audio-track-id=" "$VLC_RC" | cut -d= -f2 | head -1 | tr -d ' ')
        echo "Config audio-track-id: $AUDIO_TRACK_ID"
        
        # Audio track ID might also indicate the switch
        if [ "$RUNTIME_CAPTURED" = "false" ] && [ -n "$AUDIO_TRACK_ID" ] && [ "$AUDIO_TRACK_ID" != "0" ]; then
            AUDIO_TRACK="$AUDIO_TRACK_ID"
            TRACK_SWITCHED="true"
            VERIFICATION_METHOD="vlcrc_audio_track_id"
        fi
    fi
fi

# Determine final track status
FINAL_STATUS="unknown"
if [ "$TRACK_SWITCHED" = "true" ]; then
    FINAL_STATUS="switched"
elif [ -n "$AUDIO_TRACK" ]; then
    if [ "$AUDIO_TRACK" = "0" ] || [ "$AUDIO_TRACK" = "-1" ]; then
        FINAL_STATUS="default"
    else
        FINAL_STATUS="possibly_switched"
    fi
else
    FINAL_STATUS="unknown"
fi

# Write JSON result file
cat > /tmp/vlc_audio_track_result.json <<EOF
{
    "audio_track": "$AUDIO_TRACK",
    "audio_track_id": "$AUDIO_TRACK_ID",
    "track_switched": $TRACK_SWITCHED,
    "runtime_captured": $RUNTIME_CAPTURED,
    "verification_method": "$VERIFICATION_METHOD",
    "final_status": "$FINAL_STATUS",
    "expected_track_for_success": "1 or higher (indicating Track 2/Japanese)"
}
EOF

echo "✅ Audio track result saved to /tmp/vlc_audio_track_result.json"
cat /tmp/vlc_audio_track_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_audio_track_completed.txt
echo "Audio track: $AUDIO_TRACK" >> /tmp/vlc_audio_track_completed.txt
echo "Switched: $TRACK_SWITCHED" >> /tmp/vlc_audio_track_completed.txt
echo "Method: $VERIFICATION_METHOD" >> /tmp/vlc_audio_track_completed.txt

echo "=== Export Complete ==="