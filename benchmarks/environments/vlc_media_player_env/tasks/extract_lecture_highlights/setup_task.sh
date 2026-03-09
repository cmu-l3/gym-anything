#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract Lecture Highlights Task ==="

kill_vlc ga
sleep 1

# Create output directory
OUTPUT_DIR="/home/ga/Music/lecture_highlights"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Remove any existing output files from previous runs
rm -f "$OUTPUT_DIR"/*.mp3

# Generate a 45-minute lecture video with audio
# Using testsrc2 for more interesting visual pattern and sine wave for audio
LECTURE_VIDEO="/home/ga/Videos/lecture_video.mp4"

if [ ! -f "$LECTURE_VIDEO" ] || [ $(stat -c%s "$LECTURE_VIDEO" 2>/dev/null || echo 0) -lt 1000000 ]; then
    echo "Generating 45-minute lecture video (this may take a moment)..."
    
    # Create a 45-minute (2700 seconds) video with test pattern and audio
    # Using faster preset and lower resolution for quicker generation
    su - ga -c "ffmpeg -f lavfi -i testsrc2=duration=2700:size=1280x720:rate=15 \
        -f lavfi -i 'sine=frequency=440:duration=2700' \
        -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 28 \
        -c:a aac -b:a 64k \
        '$LECTURE_VIDEO' -y 2>/dev/null" || {
        
        echo "⚠️ Full 45-min video generation failed, creating shorter version for testing..."
        # Fallback: create 10-minute video and scale timestamps
        su - ga -c "ffmpeg -f lavfi -i testsrc2=duration=600:size=1280x720:rate=15 \
            -f lavfi -i 'sine=frequency=440:duration=600' \
            -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 28 \
            -c:a aac -b:a 64k \
            '$LECTURE_VIDEO' -y 2>/dev/null"
    }
    
    chown ga:ga "$LECTURE_VIDEO"
    echo "✅ Lecture video created: $LECTURE_VIDEO"
else
    echo "✅ Lecture video already exists: $LECTURE_VIDEO"
fi

# Verify video was created successfully
if [ ! -f "$LECTURE_VIDEO" ]; then
    echo "ERROR: Failed to create lecture video"
    exit 1
fi

VIDEO_SIZE=$(stat -c%s "$LECTURE_VIDEO")
echo "Video size: $(numfmt --to=iec-i --suffix=B $VIDEO_SIZE)"

# Create task info file with exact timestamps
cat > /home/ga/.task_info.json << 'EOF'
{
  "task_id": "extract_lecture_highlights@1",
  "source_video": "/home/ga/Videos/lecture_video.mp4",
  "output_directory": "/home/ga/Music/lecture_highlights",
  "segments": [
    {
      "id": 1,
      "start_time": "3:15",
      "end_time": "3:50",
      "start_seconds": 195,
      "end_seconds": 230,
      "duration_seconds": 35,
      "output_filename": "segment_1_concept_a.mp3",
      "description": "Concept A explanation"
    },
    {
      "id": 2,
      "start_time": "12:40",
      "end_time": "13:15",
      "start_seconds": 760,
      "end_seconds": 795,
      "duration_seconds": 35,
      "output_filename": "segment_2_concept_b.mp3",
      "description": "Concept B explanation"
    },
    {
      "id": 3,
      "start_time": "28:05",
      "end_time": "28:40",
      "start_seconds": 1685,
      "end_seconds": 1720,
      "duration_seconds": 35,
      "output_filename": "segment_3_concept_c.mp3",
      "description": "Concept C explanation"
    },
    {
      "id": 4,
      "start_time": "39:25",
      "end_time": "40:00",
      "start_seconds": 2365,
      "end_seconds": 2400,
      "duration_seconds": 35,
      "output_filename": "segment_4_concept_d.mp3",
      "description": "Concept D explanation"
    }
  ]
}
EOF

chown ga:ga /home/ga/.task_info.json

# Launch VLC (without opening the video automatically, let agent do it)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_extract_highlights_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Extract Lecture Highlights Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  Source video: /home/ga/Videos/lecture_video.mp4"
echo "  Output directory: /home/ga/Music/lecture_highlights/"
echo "  Task info (with timestamps): /home/ga/.task_info.json"
echo ""
echo "  Extract 4 audio segments:"
echo "    1. Segment 1: 3:15 - 3:50 → segment_1_concept_a.mp3"
echo "    2. Segment 2: 12:40 - 13:15 → segment_2_concept_b.mp3"
echo "    3. Segment 3: 28:05 - 28:40 → segment_3_concept_c.mp3"
echo "    4. Segment 4: 39:25 - 40:00 → segment_4_concept_d.mp3"
echo ""
echo "  Methods:"
echo "    - GUI: Media → Convert/Save, select audio profile, set times"
echo "    - CLI: cvlc with --start-time, --stop-time, and audio transcode"