#!/bin/bash
# Export script for ktv_backing_track_pipeline task
set -e

echo "=== Exporting KTV Backing Track Results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create export directory
EXPORT_DIR="/tmp/ktv_export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

# Copy catalog.json if it exists
if [ -f "/home/ga/Videos/ktv_ready/catalog.json" ]; then
    cp "/home/ga/Videos/ktv_ready/catalog.json" "$EXPORT_DIR/catalog.json"
fi

# Process each expected track
for i in 1 2 3; do
    FPATH="/home/ga/Videos/ktv_ready/track${i}_karaoke.mkv"
    if [ -f "$FPATH" ]; then
        echo "Found output for Track $i"
        
        # 1. Probe streams to JSON
        ffprobe -v error -show_format -show_streams -of json "$FPATH" > "$EXPORT_DIR/track${i}_probe.json" 2>/dev/null || true
        
        # 2. Extract 3-second audio snippet (from middle of file) for FFT analysis
        ffmpeg -y -i "$FPATH" -ss 00:00:03 -t 3 -vn -acodec pcm_s16le -ar 44100 "$EXPORT_DIR/track${i}_audio.wav" 2>/dev/null || true
        
        # 3. Extract a video frame for watermark verification
        ffmpeg -y -i "$FPATH" -ss 00:00:04 -vframes 1 "$EXPORT_DIR/track${i}_frame.png" 2>/dev/null || true
    else
        echo "Track $i not found."
    fi
done

# Compress export directory into a single tarball to be pulled by copy_from_env
cd /tmp
tar -czf ktv_export.tar.gz ktv_export/

echo "Results archived to /tmp/ktv_export.tar.gz"
echo "=== Export complete ==="