#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Crop Video Borders Task ==="

kill_vlc ga
sleep 1

# Ensure video directory exists
VIDEO_DIR="/home/ga/Videos"
mkdir -p "$VIDEO_DIR"
chown ga:ga "$VIDEO_DIR"

# Create test video with visible colored borders
# Original resolution: 1280x720
# After cropping (top:60, bottom:80, left:20, right:20): 1240x580
INPUT_VIDEO="$VIDEO_DIR/dashcam_raw.mp4"

echo "Creating test video with colored borders..."

# Generate video with colored borders and text overlays to make cropping obvious
ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=15:r=30 -vf "
    drawbox=x=0:y=0:w=1280:h=60:color=red@0.9:t=fill,
    drawbox=x=0:y=660:w=1280:h=80:color=green@0.9:t=fill,
    drawbox=x=0:y=60:w=20:h=600:color=yellow@0.9:t=fill,
    drawbox=x=1260:y=60:w=20:h=600:color=yellow@0.9:t=fill,
    drawtext=text='TOP BORDER - REMOVE 60px':x=(w-text_w)/2:y=20:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=5,
    drawtext=text='BOTTOM BORDER - REMOVE 80px':x=(w-text_w)/2:y=680:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=5,
    drawtext=text='L':x=5:y=(h-text_h)/2:fontsize=16:fontcolor=black,
    drawtext=text='R':x=1265:y=(h-text_h)/2:fontsize=16:fontcolor=black,
    drawtext=text='MAIN CONTENT AREA':x=(w-text_w)/2:y=(h-text_h)/2:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.3:boxborderw=5,
    drawtext=text='1280x720 → Crop → 1240x580':x=(w-text_w)/2:y=(h/2+40):fontsize=18:fontcolor=yellow
" -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p "$INPUT_VIDEO" -y 2>/dev/null

if [ ! -f "$INPUT_VIDEO" ]; then
    echo "ERROR: Failed to create test video"
    exit 1
fi

# Add silent audio track for completeness
TEMP_VIDEO="${INPUT_VIDEO}.tmp.mp4"
ffmpeg -i "$INPUT_VIDEO" -f lavfi -i anullsrc=r=44100:cl=stereo -c:v copy -c:a aac -shortest "$TEMP_VIDEO" -y 2>/dev/null
mv "$TEMP_VIDEO" "$INPUT_VIDEO"

# Set permissions
chown ga:ga "$INPUT_VIDEO"
chmod 644 "$INPUT_VIDEO"

echo "✅ Test video created: $INPUT_VIDEO"
echo "   Original resolution: 1280x720"
echo "   Expected after crop: 1240x580"

# Verify the created video
VIDEO_INFO=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration -of csv=p=0 "$INPUT_VIDEO" 2>/dev/null)
echo "   Video info: $VIDEO_INFO"

# Launch VLC without auto-playing
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_crop_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_crop_task.log
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

sleep 2

echo "=== Crop Video Borders Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Open the video: /home/ga/Videos/dashcam_raw.mp4"
echo "     - Use Media → Open File (Ctrl+O)"
echo ""
echo "  2. Apply crop filter:"
echo "     - Open Tools → Effects and Filters (Ctrl+E)"
echo "     - Go to 'Video Effects' tab"
echo "     - Select 'Geometry' sub-tab"
echo "     - Enable 'Crop' checkbox"
echo "     - Set crop values:"
echo "       * Top: 60"
echo "       * Bottom: 80"
echo "       * Left: 20"
echo "       * Right: 20"
echo ""
echo "  3. Export the cropped video:"
echo "     - Use Media → Convert/Save (Ctrl+R)"
echo "     - Add the source file: /home/ga/Videos/dashcam_raw.mp4"
echo "     - Click 'Convert/Save' button"
echo "     - Choose profile: Video - H.264 + MP3 (MP4)"
echo "     - Set destination: /home/ga/Videos/dashcam_cropped.mp4"
echo "     - Click 'Start'"
echo ""
echo "  NOTE: The video has colored borders to make cropping obvious"
echo "        Original: 1280x720 → After crop: 1240x580"