#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Load Subtitles Result ==="

# Query VLC RC interface for subtitle settings
SUBTITLE_FILE=""
SUBTITLE_TRACK=""
SUBTITLE_ENABLED="false"
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for subtitle track..."

    # Query subtitle track from RC interface using strack command
    RC_OUTPUT=$(echo "strack" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Parse subtitle track info
        # VLC RC returns current subtitle track, e.g., "> 1" or "( subtitle track: 1 )"
        SUBTITLE_TRACK=$(echo "$RC_OUTPUT" | grep -oP '(?:subtitle track:|>)\s*\K[\d-]+' | head -1)

        if [ -n "$SUBTITLE_TRACK" ] && [ "$SUBTITLE_TRACK" != "-1" ]; then
            SUBTITLE_ENABLED="true"
            RUNTIME_CAPTURED="true"
            echo "✅ Captured subtitle track from VLC RC: $SUBTITLE_TRACK"
        else
            echo "⚠️ No subtitle track active (track: $SUBTITLE_TRACK)"
        fi
    else
        echo "⚠️ Could not query RC interface for subtitle track"
    fi

    # Query status for more subtitle info
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$STATUS_OUTPUT" ]; then
        # Try to extract subtitle file path if present in status
        SUB_FILE=$(echo "$STATUS_OUTPUT" | grep -oP 'subtitle.*?:\s*\K[^\s]+' || echo "")
        if [ -n "$SUB_FILE" ]; then
            SUBTITLE_FILE="$SUB_FILE"
            echo "Subtitle file from status: $SUBTITLE_FILE"
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

# Fallback: Read VLC config if RC query failed
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ "$RUNTIME_CAPTURED" = "false" ] && [ -f "$VLC_RC" ]; then
    echo "Fallback to reading subtitle settings from vlcrc..."

    if grep -q "sub-file=" "$VLC_RC"; then
        SUBTITLE_FILE=$(grep "^sub-file=" "$VLC_RC" | cut -d= -f2 | head -1)
        SUBTITLE_ENABLED="true"
        echo "Subtitle file found: $SUBTITLE_FILE"
    fi

    if grep -q "sub-track=" "$VLC_RC"; then
        SUBTITLE_TRACK=$(grep "^sub-track=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Subtitle track: $SUBTITLE_TRACK"
    fi

    if grep -q "subsdec-encoding=" "$VLC_RC" || grep -q "subtitle" "$VLC_RC"; then
        SUBTITLE_ENABLED="true"
    fi
fi

# Write JSON result file
cat > /tmp/vlc_subtitles_result.json <<EOF
{
    "subtitle_file": "$SUBTITLE_FILE",
    "subtitle_track": "$SUBTITLE_TRACK",
    "subtitle_enabled": $SUBTITLE_ENABLED,
    "runtime_captured": $RUNTIME_CAPTURED,
    "source": "$([ "$RUNTIME_CAPTURED" = "true" ] && echo "rc" || echo "vlcrc")"
}
EOF

echo "✅ Subtitles result saved to /tmp/vlc_subtitles_result.json"
cat /tmp/vlc_subtitles_result.json

echo "$(date)" > /tmp/vlc_subtitles_completed.txt

echo "=== Export Complete ==="
