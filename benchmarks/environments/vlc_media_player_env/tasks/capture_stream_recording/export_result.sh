#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Capture Stream Recording Result ==="

# Check for recorded video at expected location
OUTPUT_FILE="/home/ga/Videos/captures/recorded_stream.mp4"
RECORDING_FOUND=false

if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Recording found at expected location: $OUTPUT_FILE"
    
    # Get file size
    if command -v stat &> /dev/null; then
        # Try Linux stat format first
        FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null || echo "0")
        FILE_SIZE_KB=$(echo "scale=1; $FILE_SIZE / 1024" | bc)
        echo "   File size: ${FILE_SIZE_KB} KB"
    fi
    
    ls -lh "$OUTPUT_FILE"
    
    cp "$OUTPUT_FILE" /tmp/vlc_stream_recording.mp4
    RECORDING_FOUND=true
    
    # Get basic file info
    ls -lh "$OUTPUT_FILE" > /tmp/vlc_stream_recording_info.txt 2>&1 || true
    
    # Try to get media info if ffprobe is available
    if command -v ffprobe &> /dev/null; then
        ffprobe -v error -show_format -show_streams "$OUTPUT_FILE" > /tmp/vlc_stream_recording_mediainfo.txt 2>&1 || true
    fi
else
    echo "⚠️ Recording not found at expected location: $OUTPUT_FILE"
    
    # Search for any recently created video files in captures directory
    echo "Searching for recent recordings in /home/ga/Videos/captures/..."
    
    if [ -d /home/ga/Videos/captures ]; then
        # Find files modified in last 5 minutes
        RECENT_FILES=$(find /home/ga/Videos/captures -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" -o -name "*.webm" \) -mmin -5 2>/dev/null)
        
        if [ -n "$RECENT_FILES" ]; then
            RECENT_VIDEO=$(echo "$RECENT_FILES" | head -1)
            echo "Found recent recording: $RECENT_VIDEO"
            cp "$RECENT_VIDEO" /tmp/vlc_stream_recording.mp4
            RECORDING_FOUND=true
        else
            echo "No recent video files found"
        fi
    fi
    
    if [ "$RECORDING_FOUND" = false ]; then
        echo "❌ No recording found anywhere"
        touch /tmp/vlc_stream_recording_not_found.txt
    fi
fi

# Stop HTTP server cleanly
echo "Stopping HTTP server..."
if [ -f /tmp/stream_server.pid ]; then
    SERVER_PID=$(cat /tmp/stream_server.pid)
    
    if ps -p $SERVER_PID > /dev/null 2>&1; then
        echo "Killing HTTP server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true
        sleep 1
        
        # Force kill if still running
        if ps -p $SERVER_PID > /dev/null 2>&1; then
            kill -9 $SERVER_PID 2>/dev/null || true
        fi
        
        echo "✅ HTTP server stopped"
    else
        echo "HTTP server already stopped"
    fi
    
    rm -f /tmp/stream_server.pid
fi

# Clean up stream source directory
rm -rf /tmp/stream_source 2>/dev/null || true

# Close VLC if it's still running
if is_vlc_running; then
    echo "Closing VLC..."
    
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 0.5
    fi
    
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Copy VLC logs
if [ -f /tmp/vlc_stream_task.log ]; then
    cp /tmp/vlc_stream_task.log /tmp/vlc_stream_task_export.log
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_stream_capture_completed.txt
echo "Stream recording task completed" >> /tmp/vlc_stream_capture_completed.txt
echo "Recording found: $RECORDING_FOUND" >> /tmp/vlc_stream_capture_completed.txt

echo "=== Export Complete ==="