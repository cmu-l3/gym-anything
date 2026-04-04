#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Stream Network Media Result ==="

# Initialize result variables
CURRENT_MEDIA=""
PLAYBACK_POSITION=0
PLAYBACK_STATE="unknown"
RUNTIME_CAPTURED="false"
IS_NETWORK_STREAM="false"

# Query VLC RC interface for current media and playback state
if is_vlc_running; then
    echo "Querying VLC RC interface for stream information..."

    # Query current playback info
    INFO_OUTPUT=$(echo "info" | nc -w 2 localhost:9999 2>/dev/null || echo "")

    if [ -n "$INFO_OUTPUT" ]; then
        # Extract current media URL/path
        CURRENT_MEDIA=$(echo "$INFO_OUTPUT" | grep -oP '(?:input:|file://|http://|https://|rtsp://)\K[^\s]+' | head -1)
        
        # Check if it's a network URL
        if echo "$CURRENT_MEDIA" | grep -qE '^(http://|https://|rtsp://|rtp://)'; then
            IS_NETWORK_STREAM="true"
            echo "✅ Network stream detected: $CURRENT_MEDIA"
        elif [ -n "$CURRENT_MEDIA" ]; then
            echo "⚠️ Current media is not a network stream: $CURRENT_MEDIA"
        fi
    fi

    # Query playback status
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost:9999 2>/dev/null || echo "")

    if [ -n "$STATUS_OUTPUT" ]; then
        # Parse playback state (playing, paused, stopped)
        if echo "$STATUS_OUTPUT" | grep -qi "state: playing"; then
            PLAYBACK_STATE="playing"
        elif echo "$STATUS_OUTPUT" | grep -qi "state: paused"; then
            PLAYBACK_STATE="paused"
        elif echo "$STATUS_OUTPUT" | grep -qi "state: stopped"; then
            PLAYBACK_STATE="stopped"
        fi

        # Extract playback position (in seconds)
        POSITION_RAW=$(echo "$STATUS_OUTPUT" | grep -oP '(?:position:|time:)\s*\K[\d.]+' | head -1)
        if [ -n "$POSITION_RAW" ]; then
            PLAYBACK_POSITION=$(echo "$POSITION_RAW" | awk '{printf "%.0f", $1}')
            echo "Playback position: ${PLAYBACK_POSITION}s"
        fi

        RUNTIME_CAPTURED="true"
    fi

    # Alternative: try get_time command
    if [ "$PLAYBACK_POSITION" -eq 0 ]; then
        TIME_OUTPUT=$(echo "get_time" | nc -w 2 localhost:9999 2>/dev/null || echo "")
        if [ -n "$TIME_OUTPUT" ]; then
            PLAYBACK_POSITION=$(echo "$TIME_OUTPUT" | grep -oP '\d+' | head -1)
            echo "Playback position from get_time: ${PLAYBACK_POSITION}s"
        fi
    fi
fi

# Check for playlist file
PLAYLIST_PATH="/home/ga/Videos/company_streams.m3u"
PLAYLIST_EXISTS="false"
PLAYLIST_FOUND=""

if [ -f "$PLAYLIST_PATH" ]; then
    echo "✅ Playlist found: $PLAYLIST_PATH"
    cp "$PLAYLIST_PATH" /tmp/vlc_stream_playlist.m3u
    PLAYLIST_EXISTS="true"
    PLAYLIST_FOUND="$PLAYLIST_PATH"
else
    echo "⚠️ Expected playlist not found at $PLAYLIST_PATH"
    
    # Look for any recently created playlist in Videos directory
    RECENT_PLAYLIST=$(find /home/ga/Videos -name "*.m3u" -o -name "*.xspf" -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_PLAYLIST" ]; then
        echo "Found recent playlist: $RECENT_PLAYLIST"
        cp "$RECENT_PLAYLIST" /tmp/vlc_stream_playlist.m3u
        PLAYLIST_EXISTS="true"
        PLAYLIST_FOUND="$RECENT_PLAYLIST"
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

# Stop HTTP server
if [ -f /tmp/http_server.pid ]; then
    HTTP_PID=$(cat /tmp/http_server.pid)
    if ps -p $HTTP_PID > /dev/null 2>&1; then
        echo "Stopping HTTP server (PID: $HTTP_PID)..."
        kill $HTTP_PID || true
        sleep 1
    fi
    rm /tmp/http_server.pid
fi

# Also kill any lingering http.server processes
pkill -f "http.server 8080" || true

# Write JSON result file
cat > /tmp/vlc_stream_result.json <<EOF
{
    "current_media": "$CURRENT_MEDIA",
    "is_network_stream": $IS_NETWORK_STREAM,
    "playback_state": "$PLAYBACK_STATE",
    "playback_position": $PLAYBACK_POSITION,
    "playlist_exists": $PLAYLIST_EXISTS,
    "playlist_path": "$PLAYLIST_FOUND",
    "runtime_captured": $RUNTIME_CAPTURED
}
EOF

echo "✅ Stream result saved to /tmp/vlc_stream_result.json"
cat /tmp/vlc_stream_result.json

echo "$(date)" > /tmp/vlc_stream_completed.txt
echo "Runtime captured: $RUNTIME_CAPTURED" >> /tmp/vlc_stream_completed.txt
echo "Network stream: $IS_NETWORK_STREAM" >> /tmp/vlc_stream_completed.txt

echo "=== Export Complete ==="