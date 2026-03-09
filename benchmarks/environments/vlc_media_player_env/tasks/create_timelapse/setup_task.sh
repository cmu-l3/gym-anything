#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Time-lapse Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Create necessary directories
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate source video for time-lapse
# For testing efficiency, create a 120-second video instead of 2 hours
# The video will have changing visual content (color gradients) to make time-lapse effect visible
echo "Generating source video (painting_session.mp4)..."

SOURCE_VIDEO="/home/ga/Videos/painting_session.mp4"

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found. Installing..."
    apt-get update -qq && apt-get install -y -qq ffmpeg
fi

# Create a 120-second video with changing colors and timestamp overlay
# This simulates a long recording that should be sped up
ffmpeg -f lavfi -i "color=c=0x3498db:s=1920x1080:d=120:r=30" \
  -vf "geq=r='255*sin(PI*t/20)':g='255*cos(PI*t/15)':b='255*sin(PI*t/10+1)',\
       drawtext=text='Time\: %{pts\:hms}':x=50:y=50:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10,\
       drawtext=text='Painting Session':x=(w-text_w)/2:y=h-80:fontsize=48:fontcolor=white" \
  -c:v libx264 -preset fast -crf 23 \
  -pix_fmt yuv420p \
  "$SOURCE_VIDEO" -y 2>/tmp/create_timelapse_setup.log

if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "ERROR: Failed to create source video"
    cat /tmp/create_timelapse_setup.log
    exit 1
fi

# Set ownership
chown ga:ga "$SOURCE_VIDEO"

# Get and log video info
echo "Source video created successfully:"
ffprobe -v error -show_entries format=duration -show_entries stream=width,height,r_frame_rate,codec_name \
  -of default=noprint_wrappers=1 "$SOURCE_VIDEO" 2>&1 | tee -a /tmp/create_timelapse_setup.log

SOURCE_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO" 2>/dev/null)
echo "Source duration: ${SOURCE_DURATION}s"

# Remove any existing output file
rm -f /home/ga/Videos/timelapse_output.mp4

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_timelapse_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_timelapse_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Create Time-lapse Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SOURCE: /home/ga/Videos/painting_session.mp4"
echo "  TARGET: /home/ga/Videos/timelapse_output.mp4"
echo "  GOAL:   Speed up video by 60x (create time-lapse)"
echo ""
echo "  Method 1 - VLC GUI:"
echo "    1. Open Media → Convert/Save (Ctrl+R)"
echo "    2. Add file: /home/ga/Videos/painting_session.mp4"
echo "    3. Click 'Convert/Save' button"
echo "    4. Set destination: /home/ga/Videos/timelapse_output.mp4"
echo "    5. Edit profile to adjust frame rate (multiply by 60)"
echo "    6. Disable audio"
echo "    7. Start conversion"
echo ""
echo "  Method 2 - VLC CLI (in terminal):"
echo "    cvlc /home/ga/Videos/painting_session.mp4 \\"
echo "      --sout='#transcode{vcodec=h264,vb=2000,fps=1800,acodec=none}:file{dst=/home/ga/Videos/timelapse_output.mp4}' \\"
echo "      vlc://quit"
echo ""
echo "  Expected result: ${SOURCE_DURATION}s video → ~2s video"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"