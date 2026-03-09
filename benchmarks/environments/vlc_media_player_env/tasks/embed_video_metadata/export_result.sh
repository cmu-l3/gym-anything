#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Embed Video Metadata Result ==="

OUTPUT_DIR="/tmp/task_output"
mkdir -p "$OUTPUT_DIR"

VIDEO_FILE="/home/ga/Videos/metadata_test/documentary.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Video file not found"
    echo '{"error": "video_not_found", "format": {"tags": {}}}' > "$OUTPUT_DIR/metadata_result.json"
    
    # Close VLC if running
    if is_vlc_running; then
        echo "Closing VLC..."
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid" || true
        fi
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2
    fi
    
    exit 0
fi

# Close VLC first to ensure file is flushed
if is_vlc_running; then
    echo "Closing VLC to flush file changes..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Give filesystem time to flush
sync
sleep 1

# Extract all metadata using ffprobe
echo "Extracting metadata from video file..."
ffprobe -v error \
        -show_entries format_tags=title,artist,description,copyright \
        -of json \
        "$VIDEO_FILE" > "$OUTPUT_DIR/metadata_result.json" 2>/tmp/ffprobe_error.log

# Check if ffprobe succeeded
if [ $? -ne 0 ]; then
    echo "ERROR: ffprobe failed"
    cat /tmp/ffprobe_error.log
    echo '{"error": "ffprobe_failed", "format": {"tags": {}}}' > "$OUTPUT_DIR/metadata_result.json"
fi

# Also save as plain text for debugging
ffprobe -v error \
        -show_entries format_tags=title,artist,description,copyright \
        -of default=noprint_wrappers=1 \
        "$VIDEO_FILE" > "$OUTPUT_DIR/metadata_result.txt" 2>&1 || true

# Get file info for verification
stat "$VIDEO_FILE" > "$OUTPUT_DIR/file_stats.txt" 2>&1 || true

# Check if file was modified (compare to creation time)
ls -la "$VIDEO_FILE" > "$OUTPUT_DIR/file_details.txt" 2>&1 || true

echo "Metadata extraction complete"
echo "Results saved to $OUTPUT_DIR/"

# Show extracted metadata
echo ""
echo "=== Extracted Metadata ==="
cat "$OUTPUT_DIR/metadata_result.txt" || echo "(failed to extract)"

# Create completion marker
echo "$(date)" > /tmp/vlc_metadata_completed.txt
echo "Metadata embedding task completed" >> /tmp/vlc_metadata_completed.txt

chown -R ga:ga "$OUTPUT_DIR" || true

echo "=== Export Complete ==="