#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Crop Video Region Task ==="

kill_vlc ga
sleep 1

# Create input and output directories
INPUT_DIR="/home/ga/Videos/task_input"
OUTPUT_DIR="/home/ga/Videos/task_output"

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR"
chown -R ga:ga "$INPUT_DIR" "$OUTPUT_DIR"

echo "Generating letterboxed video with hardcoded text overlay..."

# Generate a 1920x1080 video with letterbox bars (actual content is 1920x800 centered)
# The video will have:
# - 140px black bars on top and bottom
# - Text overlay in the top letterbox bar simulating burned-in subtitles
# - Actual video content in the middle (1920x800)

INPUT_VIDEO="$INPUT_DIR/letterboxed_video.mp4"

# Create test pattern video with letterbox bars and text overlay
# First create the base 1920x800 content, then pad it with black bars and add text
ffmpeg -f lavfi -i testsrc=duration=10:size=1920x800:rate=30 \
  -vf "pad=1920:1080:0:140:black,\
       drawtext=text='Hardcoded Subtitle - Episode 1':x=(w-text_w)/2:y=30:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=5,\
       drawtext=text='[Original Broadcast 2020]':x=(w-text_w)/2:y=1020:fontsize=20:fontcolor=yellow" \
  -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
  -y "$INPUT_VIDEO" 2>/dev/null

if [ ! -f "$INPUT_VIDEO" ] || [ ! -s "$INPUT_VIDEO" ]; then
    echo "ERROR: Failed to generate input video"
    exit 1
fi

echo "✅ Input video generated: $INPUT_VIDEO"

# Verify input video properties
INPUT_INFO=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration -of csv=p=0 "$INPUT_VIDEO" 2>/dev/null)
echo "Input video info: $INPUT_INFO"

# Save expected crop parameters for reference
echo "1920x800" > /tmp/expected_crop_resolution.txt
echo "top=140,bottom=140,left=0,right=0" > /tmp/expected_crop_params.txt

chown ga:ga "$INPUT_VIDEO"

# Launch VLC (don't auto-play the video, let agent open it)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_crop_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_crop_task.log 2>/dev/null || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Crop Video Region Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "A video file at:"
echo "  $INPUT_VIDEO"
echo ""
echo "contains unwanted hardcoded subtitles in letterbox bars."
echo ""
echo "Your task:"
echo "  1. Open the video in VLC"
echo "  2. Apply crop filter to remove 140 pixels from top and 140 from bottom"
echo "     (This changes resolution from 1920x1080 to 1920x800)"
echo "  3. Use Tools → Effects and Filters (Ctrl+E)"
echo "  4. Go to Video Effects → Geometry tab"
echo "  5. Enable 'Crop' and set: Top=140, Bottom=140"
echo "  6. Preview to confirm the crop looks correct"
echo "  7. Convert/save the video with crop applied:"
echo "     Media → Convert/Save (Ctrl+R)"
echo "  8. Save output to: $OUTPUT_DIR/cropped_video.mp4"
echo ""
echo "The output must have resolution 1920x800 and preserve video content."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"