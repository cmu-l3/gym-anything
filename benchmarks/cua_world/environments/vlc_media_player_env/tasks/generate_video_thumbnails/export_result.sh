#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Generate Video Thumbnails Result ==="

EXPORT_DIR="/tmp/vlc_thumbnails_export"
OUTPUT_DIR="/home/ga/Pictures/thumbnails"
TASK_DIR="/workspace/tasks/generate_video_thumbnails"

rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

# Copy all generated thumbnails
if [ -d "$OUTPUT_DIR" ]; then
    THUMBNAIL_COUNT=$(ls -1 "$OUTPUT_DIR" 2>/dev/null | wc -l)
    echo "Found $THUMBNAIL_COUNT files in output directory"
    
    if [ $THUMBNAIL_COUNT -gt 0 ]; then
        cp -r "$OUTPUT_DIR"/* "$EXPORT_DIR/" 2>/dev/null || echo "No files to copy"
        echo "✅ Copied thumbnails to export directory"
        ls -lh "$EXPORT_DIR"
    else
        echo "⚠️ No thumbnails found in output directory"
    fi
else
    echo "⚠️ Output directory not found: $OUTPUT_DIR"
    mkdir -p "$EXPORT_DIR"
fi

# Copy metadata if it exists
if [ -f "$TASK_DIR/task_metadata.json" ]; then
    cp "$TASK_DIR/task_metadata.json" "$EXPORT_DIR/"
    echo "✅ Copied task metadata"
fi

# Copy VLC logs if they exist
if [ -f "/home/ga/.config/vlc/vlc-log.txt" ]; then
    cp "/home/ga/.config/vlc/vlc-log.txt" "$EXPORT_DIR/" 2>/dev/null || true
fi

# Check for any VLC scene filter logs
if [ -f "/tmp/vlc_scene.log" ]; then
    cp "/tmp/vlc_scene.log" "$EXPORT_DIR/" 2>/dev/null || true
fi

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    kill_vlc ga
    sleep 1
fi

# Create completion marker
echo "$(date)" > "$EXPORT_DIR/task_completed.txt"
echo "Thumbnail count: $(ls -1 $OUTPUT_DIR 2>/dev/null | wc -l)" >> "$EXPORT_DIR/task_completed.txt"

# Create summary
cat > "$EXPORT_DIR/summary.txt" << EOF
Thumbnail Extraction Summary
============================
Export time: $(date)
Output directory: $OUTPUT_DIR
Thumbnails found: $(ls -1 $OUTPUT_DIR 2>/dev/null | wc -l)
Expected count: 12

Files:
$(ls -lh $OUTPUT_DIR 2>/dev/null || echo "No files found")
EOF

echo ""
echo "=== Export Summary ==="
cat "$EXPORT_DIR/summary.txt"
echo ""
echo "Export complete: $EXPORT_DIR"