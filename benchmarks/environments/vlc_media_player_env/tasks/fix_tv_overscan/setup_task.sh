#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix TV Overscan Task ==="

kill_vlc ga
sleep 1

# Create test video with edge markers if not exists
TEST_VIDEO="/home/ga/Videos/test_overscan.mp4"
if [ ! -f "$TEST_VIDEO" ]; then
    echo "Generating test video with edge markers..."
    
    # Create 30-second test video with visible edge markers
    # White borders around edges, text showing "TOP", "BOTTOM", "LEFT", "RIGHT"
    # This simulates content that would be cropped by overscan
    su - ga -c "ffmpeg -f lavfi -i color=c=black:s=1920x1080:d=30:r=25 \
           -vf \"drawbox=x=0:y=0:w=1920:h=60:color=white:t=fill,\
                drawbox=x=0:y=1020:w=1920:h=60:color=white:t=fill,\
                drawbox=x=0:y=0:w=60:h=1080:color=white:t=fill,\
                drawbox=x=1860:y=0:w=60:h=1080:color=white:t=fill,\
                drawtext=text='TOP EDGE - Would be cut off by overscan':fontsize=28:fontcolor=black:x=(w-text_w)/2:y=15,\
                drawtext=text='BOTTOM EDGE - SUBTITLE AREA':fontsize=28:fontcolor=black:x=(w-text_w)/2:y=1030,\
                drawtext=text='LEFT':fontsize=20:fontcolor=black:x=10:y=(h-text_h)/2:angle=90*PI/180,\
                drawtext=text='RIGHT':fontsize=20:fontcolor=black:x=1870:y=(h-text_h)/2:angle=90*PI/180\" \
           -c:v libx264 -pix_fmt yuv420p -preset fast -y '$TEST_VIDEO' 2>/dev/null"
    
    if [ -f "$TEST_VIDEO" ]; then
        echo "✅ Test video created: $TEST_VIDEO"
    else
        echo "⚠️ Failed to create test video, using fallback"
        # Fallback: use existing sample video
        cp /home/ga/Videos/sample_video.mp4 "$TEST_VIDEO" 2>/dev/null || true
    fi
else
    echo "✅ Test video already exists"
fi

chown ga:ga "$TEST_VIDEO" 2>/dev/null || true

# Ensure VLC config directory exists
mkdir -p /home/ga/.config/vlc
chown -R ga:ga /home/ga/.config/vlc

# Reset VLC to default state (remove existing canvas/padding filters)
VLCRC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLCRC" ]; then
    echo "Resetting VLC config to remove existing filters..."
    # Remove any existing canvas/padding/transform filters
    sed -i '/^video-filter=.*canvas/d' "$VLCRC"
    sed -i '/^vout-filter=.*canvas/d' "$VLCRC"
    sed -i '/^video-filter=.*transform/d' "$VLCRC"
    sed -i '/^canvas-/d' "$VLCRC"
    sed -i '/^transform-/d' "$VLCRC"
    sed -i '/^padding-/d' "$VLCRC"
    echo "🔄 Cleared existing canvas/padding filters from VLC config"
else
    echo "Creating new VLC config..."
    touch "$VLCRC"
    chown ga:ga "$VLCRC"
fi

# Create task instruction file
cat > /tmp/task_instructions.txt << 'EOF'
=== TASK: Fix TV Overscan ===

SCENARIO:
Your laptop is connected to an older TV via HDMI, but the TV's overscan feature
is cropping the edges of the video. The test video has WHITE EDGE MARKERS and
text that should be visible, but would be cut off on an overscanned display.

You don't have the TV remote to change overscan settings, so you need to fix
this on the VLC side by adding black padding/margins around the video.

YOUR GOAL:
Configure VLC to add black padding around ALL edges of the video (5-10% margins)
so that the entire video frame, including edge markers, would be visible on an
overscanned TV display.

METHODS TO TRY:

Method 1 - Video Effects (Easier):
1. Open: Tools → Effects and Filters (Ctrl+E)
2. Go to: Video Effects → Geometry tab
3. Look for "Canvas" or "Transform" options
4. Enable and configure padding/margins

Method 2 - Advanced Preferences:
1. Open: Tools → Preferences (Ctrl+P)
2. Click "Show settings: All" at bottom left
3. Navigate to: Video → Filters
4. Enable "Canvas filter" or "Transform filter"
5. Configure canvas width/height or padding parameters
6. Save preferences

Method 3 - Direct Filter Module:
1. Open: Tools → Preferences → Show All
2. Go to: Video → Filters → Canvas
3. Set canvas dimensions larger than video (add padding)
4. OR look for padding/margin parameters

WHAT TO CONFIGURE:
- Enable canvas or transform video filter
- Add approximately 5-10% padding on all sides
- For 1920x1080 video, canvas might be ~2080x1160 (adds 80px each side)
- Settings must persist (be saved to VLC config)

VERIFICATION:
Your VLC configuration will be checked for canvas/padding filter settings.

Test video location: /home/ga/Videos/test_overscan.mp4
EOF

chown ga:ga /tmp/task_instructions.txt

echo "Instructions saved to /tmp/task_instructions.txt"
cat /tmp/task_instructions.txt

# Launch VLC with test video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop /home/ga/Videos/test_overscan.mp4 > /tmp/vlc_overscan_task.log 2>&1 &"

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

echo "=== Fix TV Overscan Task Setup Complete ==="
echo ""
echo "📺 TASK OVERVIEW:"
echo "  Problem: TV overscan is cropping video edges"
echo "  Solution: Add black padding in VLC to prevent edge cropping"
echo "  Goal: Configure canvas/padding filter with ~5-10% margins"
echo ""
echo "📝 Quick Start:"
echo "  1. Tools → Effects and Filters (Ctrl+E)"
echo "  2. Video Effects → Geometry"
echo "  3. Enable canvas filter and add padding"
echo "  OR"
echo "  1. Tools → Preferences (Ctrl+P) → Show All"
echo "  2. Video → Filters → Canvas"
echo "  3. Configure padding parameters"
echo ""
echo "  Full instructions: /tmp/task_instructions.txt"