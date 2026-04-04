#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Pin Tutorial Window Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure wmctrl and xdotool are installed (for window management)
if ! command -v wmctrl &> /dev/null; then
    echo "Installing wmctrl..."
    apt-get update -qq && apt-get install -y -qq wmctrl > /dev/null 2>&1
fi

if ! command -v xprop &> /dev/null; then
    echo "Installing x11-utils..."
    apt-get update -qq && apt-get install -y -qq x11-utils > /dev/null 2>&1
fi

# Create tutorial video if it doesn't exist
TUTORIAL_VIDEO="/home/ga/Videos/tutorial_sample.mp4"
if [ ! -f "$TUTORIAL_VIDEO" ]; then
    echo "Creating tutorial video..."
    # Create a 30-second video with "Tutorial Content" text overlay
    ffmpeg -f lavfi -i color=c=white:s=1920x1080:d=30 \
        -vf "drawtext=text='Programming Tutorial':fontsize=72:fontcolor=black:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=white@0.5:boxborderw=10" \
        -c:v libx264 -t 30 -pix_fmt yuv420p \
        "$TUTORIAL_VIDEO" -y > /tmp/ffmpeg_tutorial.log 2>&1
    
    chown ga:ga "$TUTORIAL_VIDEO"
    echo "✅ Tutorial video created: $TUTORIAL_VIDEO"
fi

# Launch VLC with tutorial video in loop mode
echo "Launching VLC with tutorial video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$TUTORIAL_VIDEO' > /tmp/vlc_tutorial_window_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_tutorial_window_task.log
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

# Wait for window to fully render
sleep 2

echo "=== Pin Tutorial Window Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is now playing a tutorial video"
echo "  2. Enable 'Always on Top':"
echo "     - Click Video menu → Always on Top"
echo "     - OR right-click title bar → Always on Top"
echo "  3. Resize window to compact size (~640x360 pixels)"
echo "     - Drag window corners/edges to resize"
echo "  4. Move window to top-right corner"
echo "     - Drag title bar to position at top-right of screen"