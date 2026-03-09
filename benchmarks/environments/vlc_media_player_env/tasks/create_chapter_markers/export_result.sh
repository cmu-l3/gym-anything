#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Chapter Markers Result ==="

LOG="/tmp/vlc_create_chapters_export.log"
exec 1> >(tee -a "$LOG") 2>&1

EXPORT_DIR="/tmp/task_export"
mkdir -p "$EXPORT_DIR"

# Check for output video
OUTPUT_VIDEO="/home/ga/Videos/lecture_with_chapters.mp4"

if [ -f "$OUTPUT_VIDEO" ]; then
    echo "✅ Output video found: $OUTPUT_VIDEO"
    cp "$OUTPUT_VIDEO" "$EXPORT_DIR/lecture_with_chapters.mp4"
    ls -lh "$OUTPUT_VIDEO"
else
    echo "⚠️ Output video not found at expected location"
    
    # Look for any recently created video in Videos directory
    RECENT_VIDEO=$(find /home/ga/Videos -type f \( -name "*.mp4" -o -name "*.mkv" \) -mmin -10 ! -name "lecture_recording.mp4" 2>/dev/null | head -1)
    
    if [ -n "$RECENT_VIDEO" ] && [ -f "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" "$EXPORT_DIR/lecture_with_chapters.mp4"
    else
        echo "❌ No output video found"
        touch "$EXPORT_DIR/output_missing.flag"
    fi
fi

# Extract chapter metadata using ffprobe
if [ -f "$EXPORT_DIR/lecture_with_chapters.mp4" ]; then
    echo "Extracting chapter metadata..."
    ffprobe -v error -show_chapters -of json \
      "$EXPORT_DIR/lecture_with_chapters.mp4" \
      > "$EXPORT_DIR/chapters_metadata.json" 2>&1 || {
        echo "{\"chapters\": []}" > "$EXPORT_DIR/chapters_metadata.json"
        echo "⚠️ Could not extract chapters (may not exist)"
    }
    
    echo "Chapter metadata extracted"
    cat "$EXPORT_DIR/chapters_metadata.json"
fi

# Get video properties for comparison
if [ -f "$EXPORT_DIR/lecture_with_chapters.mp4" ]; then
    echo "Extracting output video properties..."
    ffprobe -v error -show_entries format=duration,size \
      -show_entries stream=codec_name,width,height \
      -of json \
      "$EXPORT_DIR/lecture_with_chapters.mp4" \
      > "$EXPORT_DIR/video_properties.json" 2>&1 || {
        echo "{}" > "$EXPORT_DIR/video_properties.json"
    }
fi

# Copy source video metadata for comparison
if [ -f /home/ga/Videos/lecture_recording.mp4 ]; then
    echo "Extracting source video properties..."
    ffprobe -v error -show_entries format=duration,size \
      -show_entries stream=codec_name,width,height \
      -of json \
      /home/ga/Videos/lecture_recording.mp4 \
      > "$EXPORT_DIR/source_properties.json" 2>&1 || {
        echo "{}" > "$EXPORT_DIR/source_properties.json"
    }
fi

# List all files in Videos directory
ls -lah /home/ga/Videos/ > "$EXPORT_DIR/videos_directory.txt" 2>&1 || true

# Check for any chapter-related files created
find /home/ga/Videos/chapters/ -type f -mmin -10 2>/dev/null > "$EXPORT_DIR/chapter_files.txt" || true
find /tmp -name "*chapter*" -type f -mmin -10 2>/dev/null >> "$EXPORT_DIR/chapter_files.txt" || true

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" 2>/dev/null || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga || true
    fi
fi

# Create completion marker
echo "$(date)" > "$EXPORT_DIR/task_completed.txt"
echo "Chapter markers task export completed" >> "$EXPORT_DIR/task_completed.txt"

echo ""
echo "=== Export Complete ==="
echo "Files in export directory:"
ls -lah "$EXPORT_DIR/" || true