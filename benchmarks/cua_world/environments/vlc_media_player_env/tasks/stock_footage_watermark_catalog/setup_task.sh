#!/bin/bash
echo "=== Setting up stock_footage_watermark_catalog task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Kill existing VLC instances to start clean
pkill -u ga -f vlc || true

# Create directories
mkdir -p /home/ga/Videos/raw_footage
mkdir -p /home/ga/Videos/previews
mkdir -p /home/ga/Documents

echo "Generating raw footage files..."
# Generate source videos using complex test sources for realism
ffmpeg -y -f lavfi -i "mandelbrot=size=1920x1080:rate=30" -t 40 -c:v libx264 -preset ultrafast -crf 23 /home/ga/Videos/raw_footage/aerial_landscape_001.mp4 2>/dev/null
ffmpeg -y -f lavfi -i "life=size=1920x1080:rate=30:mold=10:ratio=0.1" -f lavfi -i "sine=frequency=440:duration=35" -t 35 -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 128k /home/ga/Videos/raw_footage/nature_wildlife_002.mp4 2>/dev/null
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30" -t 45 -c:v libx264 -preset ultrafast -crf 23 /home/ga/Videos/raw_footage/urban_timelapse_003.mp4 2>/dev/null

echo "Generating preview specification..."
cat > /home/ga/Documents/preview_spec.txt << 'EOF'
=== STOCK FOOTAGE PREVIEW SPECIFICATION ===
Output Directory: /home/ga/Videos/previews/

For each raw clip in /home/ga/Videos/raw_footage/, produce:

1. Preview Video
   - Filename: preview_[original_filename] (e.g., preview_aerial_landscape_001.mp4)
   - Resolution: 1280x720
   - Duration: First 15 seconds only
   - Codec: H.264 video, keep audio if present (AAC)
   - Watermark: Large "PREVIEW" text overlay (visible, semi-transparent)
   - Timecode: Burned-in timecode, timer, or counter visible in the frame (e.g., HH:MM:SS or seconds)

2. Thumbnail
   - Filename: thumb_[original_filename without .mp4].png (e.g., thumb_aerial_landscape_001.png)
   - Format: PNG
   - Width: At least 640px
   - Content: Extracted at approximately the 5-second mark

3. Catalog (one file for all clips)
   - Filename: catalog.json (must be inside /home/ga/Videos/previews/)
   - Format: JSON array of objects
   - Required fields per object:
     - "source_filename": string
     - "preview_filename": string
     - "thumbnail_filename": string
     - "source_duration_seconds": number
     - "preview_duration_seconds": number
     - "preview_resolution": string (e.g., "1280x720")
     - "preview_file_size_bytes": number
EOF

# Set proper permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Launch VLC with no file loaded so agent can use it or fallback to CLI
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 3

# Take initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="