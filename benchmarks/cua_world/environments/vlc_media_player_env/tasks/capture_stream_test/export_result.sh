#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Capture Stream Test Result ==="

# Expected recording file
RECORDING_FILE="/home/ga/Videos/stream_test_capture.mp4"

# Check for recording file
if [ -f "$RECORDING_FILE" ]; then
    echo "✅ Recording found: $RECORDING_FILE"
    cp "$RECORDING_FILE" /tmp/vlc_stream_capture.mp4
    ls -lh "$RECORDING_FILE"
else
    echo "⚠️ Expected recording not found"
    
    # Look for any recently created video files in Videos directory
    echo "Searching for recent recordings..."
    RECENT_VIDEO=$(find /home/ga/Videos -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -5 2>/dev/null | grep -v "sample_video\|color_test" | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" /tmp/vlc_stream_capture.mp4
    else
        echo "❌ No recording file found"
        # Create empty file to avoid verification failure
        touch /tmp/vlc_stream_capture_not_found.txt
    fi
fi

# Stop HTTP server
if [ -f /tmp/http_stream_server.pid ]; then
    HTTP_PID=$(cat /tmp/http_stream_server.pid)
    if ps -p "$HTTP_PID" > /dev/null 2>&1; then
        echo "Stopping HTTP server (PID: $HTTP_PID)..."
        kill "$HTTP_PID" || true
        sleep 1
    fi
    rm -f /tmp/http_stream_server.pid
fi

# Also cleanup any remaining http.server processes
pkill -f "python.*http.server.*8080" || true

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

# Force kill if still running
if is_vlc_running; then
    echo "Force closing VLC..."
    kill_vlc ga
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_stream_capture_completed.txt
echo "Stream capture test completed" >> /tmp/vlc_stream_capture_completed.txt

echo "=== Export Complete ==="