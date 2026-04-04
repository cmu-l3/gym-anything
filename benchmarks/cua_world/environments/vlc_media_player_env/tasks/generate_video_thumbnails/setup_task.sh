#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Generate Video Thumbnails Task ==="

kill_vlc ga
sleep 1

TASK_DIR="/workspace/tasks/generate_video_thumbnails"
OUTPUT_DIR="/home/ga/Pictures/thumbnails"
VIDEO_PATH="/home/ga/Videos/raw_footage.mp4"
DURATION=1500  # 25 minutes in seconds

# Clean previous outputs
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"

# Generate a sample video if it doesn't exist (25 minutes long with varying content)
if [ ! -f "$VIDEO_PATH" ]; then
    echo "Generating sample raw footage video with varying scenes..."
    
    # Create video with changing color scenes to ensure thumbnails will be visibly different
    # 5 segments of 5 minutes each (300s each) with different colors
    su - ga -c "ffmpeg -f lavfi -i 'color=c=blue:s=1280x720:d=300' \
        -f lavfi -i 'color=c=green:s=1280x720:d=300' \
        -f lavfi -i 'color=c=red:s=1280x720:d=300' \
        -f lavfi -i 'color=c=yellow:s=1280x720:d=300' \
        -f lavfi -i 'color=c=purple:s=1280x720:d=300' \
        -filter_complex '[0:v][1:v][2:v][3:v][4:v]concat=n=5:v=1:a=0[out]' \
        -map '[out]' -c:v libx264 -preset ultrafast -r 30 -t $DURATION '$VIDEO_PATH' -y" 2>&1 | tee /tmp/ffmpeg_generate.log
    
    echo "Sample video generated: $VIDEO_PATH"
fi

# Verify video exists and get duration
if [ ! -f "$VIDEO_PATH" ]; then
    echo "ERROR: Video file not found at $VIDEO_PATH"
    exit 1
fi

# Get actual duration and frame rate
echo "Analyzing video properties..."
ACTUAL_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_PATH" 2>/dev/null | cut -d'.' -f1 || echo "1500")
VIDEO_FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$VIDEO_PATH" 2>/dev/null | head -1 || echo "30/1")

# Calculate FPS as decimal
if [[ "$VIDEO_FPS" == *"/"* ]]; then
    FPS_NUM=$(echo "$VIDEO_FPS" | cut -d'/' -f1)
    FPS_DEN=$(echo "$VIDEO_FPS" | cut -d'/' -f2)
    FPS=$(echo "scale=2; $FPS_NUM / $FPS_DEN" | bc)
else
    FPS="$VIDEO_FPS"
fi

echo "Video duration: ${ACTUAL_DURATION}s"
echo "Video FPS: $FPS"

# Calculate total frames and scene ratio for 12 thumbnails
TOTAL_FRAMES=$(echo "$ACTUAL_DURATION * $FPS" | bc | cut -d'.' -f1)
SCENE_RATIO=$(echo "$TOTAL_FRAMES / 12" | bc)

echo "Total frames: $TOTAL_FRAMES"
echo "Scene ratio for 12 thumbnails: $SCENE_RATIO"

# Create instruction file on desktop
cat > /home/ga/Desktop/TASK_INSTRUCTIONS.txt << EOF
VIDEO THUMBNAIL EXTRACTION TASK
================================

OBJECTIVE:
Extract exactly 12 thumbnail images evenly distributed throughout 
the video at /home/ga/Videos/raw_footage.mp4

REQUIREMENTS:
✓ Use VLC's scene filter to extract frames
✓ Save thumbnails to: /home/ga/Pictures/thumbnails/
✓ Extract exactly 12 images spanning the entire video duration
✓ Images should be evenly spaced throughout the video

VIDEO INFO:
- Path: $VIDEO_PATH
- Duration: ${ACTUAL_DURATION}s (~$(echo "$ACTUAL_DURATION / 60" | bc) minutes)
- Frame rate: $FPS fps
- Total frames: $TOTAL_FRAMES

HINT - VLC Scene Filter:
The scene filter can automatically extract frames at regular intervals.
You can use it via CLI like this:

cvlc --video-filter=scene --scene-path=/home/ga/Pictures/thumbnails \\
     --scene-ratio=N --scene-prefix=thumb_ \\
     --scene-format=png /home/ga/Videos/raw_footage.mp4 vlc://quit

Where:
- scene-ratio=N means "save every Nth frame"
- scene-path is where to save images
- scene-prefix is the filename prefix
- vlc://quit exits after processing

CALCULATION:
1. Get video duration and frame rate using ffprobe
2. Calculate total frames: duration × fps
3. Calculate scene-ratio: total_frames / 12

Example calculation for this video:
- Total frames = $ACTUAL_DURATION × $FPS = $TOTAL_FRAMES
- Scene ratio = $TOTAL_FRAMES / 12 ≈ $SCENE_RATIO

HINT - Getting Video Info:
ffprobe -v error -select_streams v:0 \\
  -show_entries stream=r_frame_rate,duration \\
  -of default=noprint_wrappers=1 /home/ga/Videos/raw_footage.mp4

Good luck!
EOF

chown ga:ga /home/ga/Desktop/TASK_INSTRUCTIONS.txt

# Store metadata for verifier
mkdir -p "$TASK_DIR"
cat > "$TASK_DIR/task_metadata.json" << EOF
{
  "video_path": "$VIDEO_PATH",
  "output_dir": "$OUTPUT_DIR",
  "expected_count": 12,
  "video_duration": $ACTUAL_DURATION,
  "video_fps": $FPS,
  "total_frames": $TOTAL_FRAMES,
  "calculated_scene_ratio": $SCENE_RATIO,
  "max_time_seconds": 180
}
EOF

echo "Metadata saved to $TASK_DIR/task_metadata.json"
cat "$TASK_DIR/task_metadata.json"

echo ""
echo "=== Generate Video Thumbnails Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Analyze video: $VIDEO_PATH (${ACTUAL_DURATION}s)"
echo "  2. Calculate scene-ratio for exactly 12 thumbnails"
echo "  3. Use VLC scene filter to extract frames"
echo "  4. Save to: $OUTPUT_DIR"
echo "  5. Calculated scene-ratio: $SCENE_RATIO (for reference)"