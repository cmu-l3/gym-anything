#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Record Network Stream Result ==="

RECORDINGS_DIR="/home/ga/Videos/recordings"
EXPECTED_OUTPUT="$RECORDINGS_DIR/captured_webinar.mp4"

# Check if expected recording exists
if [ -f "$EXPECTED_OUTPUT" ]; then
    echo "✅ Recording found at expected location: $EXPECTED_OUTPUT"
    
    # Get file info
    FILE_SIZE=$(stat -f%z "$EXPECTED_OUTPUT" 2>/dev/null || stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    FILE_SIZE_KB=$((FILE_SIZE / 1024))
    
    echo "File size: ${FILE_SIZE_KB} KB"
    ls -lh "$EXPECTED_OUTPUT"
    
    # Quick validation with ffprobe
    echo "Analyzing recorded video..."
    ffprobe -v error -show_entries format=duration,size,format_name \
            -show_entries stream=codec_name,width,height \
            -of default=noprint_wrappers=1 \
            "$EXPECTED_OUTPUT" 2>&1 | tee /tmp/vlc_recording_info.txt || echo "Warning: ffprobe analysis failed"
    
    # Copy to temp location for verification
    cp "$EXPECTED_OUTPUT" /tmp/vlc_recorded_stream.mp4
    echo "✅ Recording copied to /tmp/vlc_recorded_stream.mp4 for verification"
    
else
    echo "⚠️ Expected recording not found at: $EXPECTED_OUTPUT"
    echo "Searching for any recent recordings in $RECORDINGS_DIR..."
    
    # Look for any recently created video files
    RECENT_RECORDING=$(find "$RECORDINGS_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -5 2>/dev/null | head -1)
    
    if [ -n "$RECENT_RECORDING" ]; then
        echo "Found recent recording: $RECENT_RECORDING"
        
        FILE_SIZE=$(stat -f%z "$RECENT_RECORDING" 2>/dev/null || stat -c%s "$RECENT_RECORDING" 2>/dev/null || echo "0")
        FILE_SIZE_KB=$((FILE_SIZE / 1024))
        echo "File size: ${FILE_SIZE_KB} KB"
        
        # Copy it for verification
        cp "$RECENT_RECORDING" /tmp/vlc_recorded_stream.mp4
        echo "✅ Recording copied for verification"
    else
        echo "❌ No recordings found in $RECORDINGS_DIR"
        echo "Directory contents:"
        ls -la "$RECORDINGS_DIR/" || echo "Directory not accessible"
        
        # Create an empty marker file to indicate failure
        touch /tmp/vlc_recording_not_found.txt
    fi
fi

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Try graceful close
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force close if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
cat > /tmp/vlc_record_completed.txt <<EOF
Task completed at: $(date)
Expected output: $EXPECTED_OUTPUT
Recording exists: $([ -f "$EXPECTED_OUTPUT" ] && echo "yes" || echo "no")
EOF

echo "=== Export Complete ==="