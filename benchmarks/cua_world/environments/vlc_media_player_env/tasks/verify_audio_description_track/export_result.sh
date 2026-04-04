#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Audio Description Track Verification Result ==="

# Initialize result variables
AUDIO_TRACK=""
AUDIO_TRACK_NAME=""
RUNTIME_CAPTURED="false"
TRACK_CHANGED="false"

# Query VLC RC interface for current audio track
if is_vlc_running; then
    echo "Querying VLC RC interface for audio track selection..."
    
    # Query audio track using atrack command
    # VLC RC returns: "( audio track: N )" or "> N" where N is track number
    RC_OUTPUT=$(echo "atrack" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_OUTPUT" ]; then
        echo "RC atrack output: $RC_OUTPUT"
        
        # Extract track number from RC output
        # Format can be: "> 1" or "( audio track: 1 )" or "status: ( new audio track: 1 )"
        AUDIO_TRACK=$(echo "$RC_OUTPUT" | grep -oP '(?:audio track:|new audio track:|>)\s*\K[\d-]+' | head -1)
        
        if [ -n "$AUDIO_TRACK" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured audio track from VLC RC: Track $AUDIO_TRACK"
            
            # Check if track was changed from default (-1 or 0)
            if [ "$AUDIO_TRACK" != "-1" ] && [ "$AUDIO_TRACK" != "0" ]; then
                TRACK_CHANGED="true"
                echo "✅ Audio track was explicitly changed (not default)"
            else
                echo "⚠️ Audio track still at default value: $AUDIO_TRACK"
            fi
        else
            echo "⚠️ Could not parse audio track number from RC output"
        fi
    else
        echo "⚠️ Could not query RC interface for audio track"
    fi
    
    # Also query status for additional info
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$STATUS_OUTPUT" ]; then
        # Try to extract audio track info from status
        STATUS_TRACK=$(echo "$STATUS_OUTPUT" | grep -oP 'audio.*?track.*?\K\d+' | head -1)
        if [ -n "$STATUS_TRACK" ] && [ -z "$AUDIO_TRACK" ]; then
            AUDIO_TRACK="$STATUS_TRACK"
            RUNTIME_CAPTURED="true"
            echo "Captured audio track from status: $STATUS_TRACK"
        fi
    fi
else
    echo "⚠️ VLC is not running"
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
        echo "Force killing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Fallback: Read VLC config if RC query failed
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ "$RUNTIME_CAPTURED" = "false" ] && [ -f "$VLC_RC" ]; then
    echo "Fallback: reading audio track from vlcrc..."
    
    if grep -q "^audio-track=" "$VLC_RC"; then
        AUDIO_TRACK=$(grep "^audio-track=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Audio track from config: $AUDIO_TRACK"
        
        # Check if it's not default
        if [ "$AUDIO_TRACK" != "-1" ] && [ -n "$AUDIO_TRACK" ]; then
            TRACK_CHANGED="true"
        fi
    fi
fi

# Verify the test video exists and has correct properties
TEST_VIDEO="/home/ga/Videos/accessibility_test/wildlife_doc.mp4"
VIDEO_EXISTS="false"
AUDIO_TRACK_COUNT=0

if [ -f "$TEST_VIDEO" ]; then
    VIDEO_EXISTS="true"
    AUDIO_TRACK_COUNT=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$TEST_VIDEO" 2>/dev/null | wc -l || echo "0")
    echo "Test video verified: $AUDIO_TRACK_COUNT audio tracks"
fi

# Write JSON result file
cat > /tmp/vlc_ad_track_result.json <<EOF
{
    "audio_track": "$AUDIO_TRACK",
    "audio_track_name": "$AUDIO_TRACK_NAME",
    "track_changed": $TRACK_CHANGED,
    "runtime_captured": $RUNTIME_CAPTURED,
    "video_exists": $VIDEO_EXISTS,
    "audio_track_count": $AUDIO_TRACK_COUNT,
    "source": "$([ "$RUNTIME_CAPTURED" = "true" ] && echo "rc" || echo "vlcrc")"
}
EOF

echo ""
echo "✅ Audio description track result saved to /tmp/vlc_ad_track_result.json"
cat /tmp/vlc_ad_track_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_ad_track_completed.txt
echo "Audio track selected: $AUDIO_TRACK" >> /tmp/vlc_ad_track_completed.txt
echo "Track changed from default: $TRACK_CHANGED" >> /tmp/vlc_ad_track_completed.txt

echo ""
echo "=== Export Complete ==="