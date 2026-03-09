#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sync External Audio Result ==="

# Initialize result variables
AUDIO_TRACK_COUNT=1
ACTIVE_AUDIO_TRACK=1
EXTERNAL_AUDIO_LOADED="false"
RUNTIME_CAPTURED="false"
INITIAL_TRACK=1

# Read initial track state
if [ -f /tmp/vlc_initial_atrack.txt ]; then
    INITIAL_TRACK=$(cat /tmp/vlc_initial_atrack.txt)
    echo "Initial audio track was: $INITIAL_TRACK"
fi

if is_vlc_running; then
    echo "Querying VLC RC interface for audio track state..."

    # Query current audio track
    ATRACK_OUTPUT=$(echo "atrack" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$ATRACK_OUTPUT" ]; then
        # Parse active audio track
        # VLC RC returns format like "> 2" or "( audio track: 2 )"
        ACTIVE_AUDIO_TRACK=$(echo "$ATRACK_OUTPUT" | grep -oP '(?:audio track:|>)\s*\K[\d-]+' | head -1 || echo "1")
        
        echo "Active audio track: $ACTIVE_AUDIO_TRACK"
        
        # Count available audio tracks by trying to get track info
        # VLC typically shows track indices when queried
        TRACK_LIST=$(echo "$ATRACK_OUTPUT" | grep -oP '\d+' || echo "")
        AUDIO_TRACK_COUNT=$(echo "$TRACK_LIST" | wc -l)
        
        # Alternative: check if we can detect multiple tracks from the output
        if echo "$ATRACK_OUTPUT" | grep -qE "(Track [2-9]|track [2-9]|\| 2 \|)"; then
            AUDIO_TRACK_COUNT=2
            echo "✅ Multiple audio tracks detected"
        fi
        
        # Check if active track is different from initial (indicates change)
        if [ "$ACTIVE_AUDIO_TRACK" != "$INITIAL_TRACK" ] && [ "$ACTIVE_AUDIO_TRACK" -ge 2 ]; then
            EXTERNAL_AUDIO_LOADED="true"
            RUNTIME_CAPTURED="true"
            echo "✅ External audio track is active (Track $ACTIVE_AUDIO_TRACK)"
        else
            echo "⚠️ Audio track unchanged or still on original (Track $ACTIVE_AUDIO_TRACK)"
        fi
    else
        echo "⚠️ Could not query audio track from RC interface"
    fi
    
    # Additional check: query VLC status for more details
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$STATUS_OUTPUT" ]; then
        # Check for indicators of multiple audio streams
        if echo "$STATUS_OUTPUT" | grep -qiE "(audio|stream).*2"; then
            echo "Status indicates multiple audio streams"
            AUDIO_TRACK_COUNT=2
        fi
    fi
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

# Fallback: Check VLC logs for evidence of loading external audio
VLC_LOG="/tmp/vlc_audio_sync_task.log"
if [ -f "$VLC_LOG" ]; then
    if grep -qiE "(added audio|audio track|loading.*audio|replacement_audio)" "$VLC_LOG"; then
        echo "VLC log shows evidence of external audio loading"
        if [ "$RUNTIME_CAPTURED" = "false" ]; then
            EXTERNAL_AUDIO_LOADED="true"
            AUDIO_TRACK_COUNT=2
        fi
    fi
fi

# Fallback: Check VLC config (though external tracks usually aren't persisted)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ "$RUNTIME_CAPTURED" = "false" ] && [ -f "$VLC_RC" ]; then
    echo "Checking VLC config for audio track settings..."
    
    if grep -qE "^audio-track=" "$VLC_RC"; then
        TRACK_VALUE=$(grep "^audio-track=" "$VLC_RC" | cut -d= -f2 | head -1)
        if [ -n "$TRACK_VALUE" ] && [ "$TRACK_VALUE" -ge 2 ]; then
            ACTIVE_AUDIO_TRACK="$TRACK_VALUE"
            echo "Config shows audio track: $TRACK_VALUE"
        fi
    fi
fi

# Write JSON result file
cat > /tmp/vlc_audio_sync_result.json <<EOF
{
    "audio_track_count": $AUDIO_TRACK_COUNT,
    "active_audio_track": $ACTIVE_AUDIO_TRACK,
    "initial_audio_track": $INITIAL_TRACK,
    "external_audio_loaded": $EXTERNAL_AUDIO_LOADED,
    "track_changed": $([ "$ACTIVE_AUDIO_TRACK" != "$INITIAL_TRACK" ] && echo "true" || echo "false"),
    "runtime_captured": $RUNTIME_CAPTURED,
    "source": "$([ "$RUNTIME_CAPTURED" = "true" ] && echo "rc" || echo "fallback")"
}
EOF

echo "✅ Audio sync result saved to /tmp/vlc_audio_sync_result.json"
cat /tmp/vlc_audio_sync_result.json

echo "$(date)" > /tmp/vlc_audio_sync_completed.txt
echo "External audio sync task completed" >> /tmp/vlc_audio_sync_completed.txt
echo "Audio tracks: $AUDIO_TRACK_COUNT" >> /tmp/vlc_audio_sync_completed.txt
echo "Active track: $ACTIVE_AUDIO_TRACK" >> /tmp/vlc_audio_sync_completed.txt

echo "=== Export Complete ==="