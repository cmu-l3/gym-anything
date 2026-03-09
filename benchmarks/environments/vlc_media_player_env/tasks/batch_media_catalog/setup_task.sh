#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Batch Media Catalog Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create catalog queue directory
CATALOG_DIR="/home/ga/Videos/catalog_queue"
mkdir -p "$CATALOG_DIR"

# Ensure output directories exist
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Pictures

echo "Generating sample videos for cataloging..."

# Video 1: 1920x1080, 45 seconds, MP4
echo "Creating video_01.mp4 (1920x1080, 45s)..."
ffmpeg -f lavfi -i testsrc=duration=45:size=1920x1080:rate=30 \
    -f lavfi -i sine=frequency=440:duration=45 \
    -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 128k \
    "$CATALOG_DIR/video_01.mp4" -y 2>/dev/null

# Video 2: 1280x720, 62 seconds, MKV
echo "Creating video_02.mkv (1280x720, 62s)..."
ffmpeg -f lavfi -i testsrc=duration=62:size=1280x720:rate=30 \
    -f lavfi -i sine=frequency=523:duration=62 \
    -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 128k \
    "$CATALOG_DIR/video_02.mkv" -y 2>/dev/null

# Video 3: 854x480, 38 seconds, AVI
echo "Creating video_03.avi (854x480, 38s)..."
ffmpeg -f lavfi -i testsrc=duration=38:size=854x480:rate=30 \
    -f lavfi -i sine=frequency=330:duration=38 \
    -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 23 -c:a mp3 -b:a 128k \
    "$CATALOG_DIR/video_03.avi" -y 2>/dev/null

# Video 4: 1920x1080, 51 seconds, MP4
echo "Creating video_04.mp4 (1920x1080, 51s)..."
ffmpeg -f lavfi -i testsrc=duration=51:size=1920x1080:rate=30 \
    -f lavfi -i sine=frequency=392:duration=51 \
    -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 128k \
    "$CATALOG_DIR/video_04.mp4" -y 2>/dev/null

# Verify files were created
for i in 1 2 3 4; do
    if [ $i -eq 1 ] || [ $i -eq 4 ]; then
        FILE="$CATALOG_DIR/video_0${i}.mp4"
    elif [ $i -eq 2 ]; then
        FILE="$CATALOG_DIR/video_0${i}.mkv"
    else
        FILE="$CATALOG_DIR/video_0${i}.avi"
    fi
    
    if [ ! -f "$FILE" ]; then
        echo "ERROR: Failed to create $FILE"
        exit 1
    fi
    echo "✅ Created $FILE ($(du -h "$FILE" | cut -f1))"
done

# Set proper permissions
chown -R ga:ga "$CATALOG_DIR"
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Pictures

echo "=== Batch Media Catalog Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  You have 4 video files in /home/ga/Videos/catalog_queue/"
echo "  "
echo "  Your task:"
echo "  1. Inspect each video file to determine its properties"
echo "  2. Create a catalog report at /home/ga/Documents/media_catalog.txt"
echo "  3. Take a snapshot from the mid-point of each video"
echo "  4. Save snapshots to /home/ga/Pictures/catalog_snapshots/"
echo "  "
echo "  Required information for each file:"
echo "  - Playback status (Playable/Not playable)"
echo "  - Duration (MM:SS format)"
echo "  - Resolution (WIDTHxHEIGHT)"
echo "  - File size (MB)"
echo "  - Snapshot filename"
echo "  "
echo "  You can use:"
echo "  - VLC to open files and take snapshots"
echo "  - Command-line tools like ffprobe or mediainfo"
echo "  - File manager to check file sizes"
echo ""