#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Zoom Video Region Task ==="

kill_vlc ga
sleep 1

# Ensure video directory exists
VIDEO_DIR="/home/ga/Videos"
mkdir -p "$VIDEO_DIR"
chown ga:ga "$VIDEO_DIR"

# Generate tutorial video with small text overlay simulating a high-DPI screen recording
TUTORIAL_VIDEO="$VIDEO_DIR/tutorial_hires.mp4"

echo "Creating tutorial video with small text..."

# Create a 1920x1080 video with small text elements (simulating tutorial with small UI)
ffmpeg -f lavfi -i "color=c=white:s=1920x1080:d=30:r=30" \
    -vf "drawbox=x=1400:y=40:w=480:h=300:color=lightgray@0.8:t=fill,\
         drawtext=text='Tutorial Step 1\: Click Settings':fontsize=20:fontcolor=black:x=1420:y=60:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf,\
         drawtext=text='Step 2\: Find Advanced tab':fontsize=16:fontcolor=darkblue:x=1420:y=100:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf,\
         drawtext=text='[Save] [Load] [Export] [Help]':fontsize=14:fontcolor=gray:x=1420:y=140:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf,\
         drawtext=text='Toolbar\: File Edit View':fontsize=14:fontcolor=black:x=1420:y=180:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf,\
         drawtext=text='Status\: Ready | CPU\: 45%':fontsize=12:fontcolor=green:x=1420:y=220:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf,\
         drawtext=text='This text is difficult to read at normal size':fontsize=18:fontcolor=red:x=1420:y=280:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf,\
         drawtext=text='ZOOM NEEDED':fontsize=24:fontcolor=darkred:x=960:y=540:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
    -c:v libx264 -preset ultrafast -crf 23 -t 30 \
    "$TUTORIAL_VIDEO" -y 2>/dev/null || {
    echo "ERROR: Failed to create tutorial video"
    exit 1
}

# Verify video was created
if [ ! -f "$TUTORIAL_VIDEO" ]; then
    echo "ERROR: Tutorial video not found after creation"
    exit 1
fi

chown ga:ga "$TUTORIAL_VIDEO"
echo "✅ Tutorial video created: $TUTORIAL_VIDEO"

# Reset VLC config to ensure zoom is disabled initially
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

mkdir -p "$VLC_CONFIG_DIR"
chown ga:ga "$VLC_CONFIG_DIR"

# Create clean vlcrc with zoom explicitly disabled
cat > "$VLC_RC" <<EOF
# VLC preferences - Clean state (no zoom)
[core]
metadata-network-access=0

[qt]
qt-privacy-ask=0
qt-continue=0
qt-start-minimized=0

[video]
video-on-top=0
interactive-zoom=0
zoom=1.000000

# Disable hardware acceleration for stability
[avcodec]
avcodec-hw=none
EOF

chown ga:ga "$VLC_RC"
echo "✅ VLC config reset (zoom disabled)"

# Create instruction file
WORKSPACE_DIR="/home/ga/workspace"
mkdir -p "$WORKSPACE_DIR"

cat > "$WORKSPACE_DIR/zoom_instructions.txt" <<EOF
ZOOM VIDEO REGION TASK

Video: $TUTORIAL_VIDEO

GOAL: Configure VLC to zoom the video by 200% (2x magnification)

INSTRUCTIONS:
1. The video contains small text in the upper-right area
2. Open Tools → Effects and Filters (or press Ctrl+E)
3. Navigate to: Video Effects → Geometry tab
4. Check the "Interactive Zoom" checkbox to enable zoom
5. Adjust the zoom slider/factor to 2.0 (200%)
6. Close the dialog - zoom should now be applied

VERIFICATION:
- The center of the video will be magnified 2x
- Small text should become more readable
- Settings will be saved to VLC config

HINTS:
- Look for "Geometry" or "Transform" in Video Effects
- Zoom factor 1.0 = normal, 2.0 = 200% magnification
- Interactive zoom allows mouse control (optional)
EOF

chown ga:ga "$WORKSPACE_DIR/zoom_instructions.txt"

# Launch VLC with tutorial video
echo "Launching VLC with tutorial video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$TUTORIAL_VIDEO' > /tmp/vlc_zoom_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_zoom_task.log
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

# Wait for video to fully load
sleep 2

echo "=== Zoom Video Region Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video playing with small text in upper-right corner"
echo "  2. Open: Tools → Effects and Filters (Ctrl+E)"
echo "  3. Navigate to: Video Effects → Geometry tab"
echo "  4. Enable: 'Interactive Zoom' checkbox"
echo "  5. Set zoom factor to: 2.0 (200%)"
echo "  6. Close dialog to apply zoom"
echo ""
echo "  See: $WORKSPACE_DIR/zoom_instructions.txt for details"