#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up A-B Repeat Loop Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure necessary directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Desktop

# Generate a sample interview video (60 seconds long)
# Use testsrc with some visual markers and audio tone
echo "Generating interview video..."
if [ ! -f /home/ga/Videos/research_interview.mp4 ]; then
    ffmpeg -f lavfi -i "testsrc=duration=60:size=1280x720:rate=30" \
        -f lavfi -i "sine=frequency=440:duration=60" \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
        -c:a aac -b:a 128k \
        /home/ga/Videos/research_interview.mp4 -y \
        > /tmp/vlc_ab_loop_ffmpeg.log 2>&1
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to generate interview video"
        cat /tmp/vlc_ab_loop_ffmpeg.log
        exit 1
    fi
fi

# Verify file was created
if [ ! -f /home/ga/Videos/research_interview.mp4 ]; then
    echo "ERROR: Interview video file not found after generation"
    exit 1
fi

# Set ownership
chown -R ga:ga /home/ga/Videos/research_interview.mp4

echo "✅ Interview video ready: $(ls -lh /home/ga/Videos/research_interview.mp4)"

# Create a desktop instruction file
cat > /home/ga/Desktop/AB_LOOP_TASK.txt << 'EOF'
═══════════════════════════════════════════════
  TRANSCRIPTION TASK: A-B REPEAT LOOP
═══════════════════════════════════════════════

You are helping a PhD student transcribe an interview.

TARGET SEGMENT TO LOOP:
  From: 15 seconds (0:15)
  To:   30 seconds (0:30)

YOUR TASK:
1. Open /home/ga/Videos/research_interview.mp4 in VLC (already playing)
2. Set up A-B repeat to loop the segment from 15s to 30s
3. Make sure the loop is active and playing

HOW TO SET A-B REPEAT:
  Method 1 (Keyboard):
    - Seek to 15 seconds
    - Press Shift+L (or just L) to set Point A
    - Seek to 30 seconds  
    - Press Shift+L again to set Point B
    - Video should now loop between these points

  Method 2 (Menu):
    - Playback → A→B Loop (or Loop → A→B)
    - Click once at 15s to set A
    - Click again at 30s to set B

NAVIGATION TIPS:
  - Click on timeline to seek
  - Shift+Right: Jump forward 5 seconds
  - Shift+Left: Jump backward 5 seconds
  - Space: Pause/Play

VERIFICATION:
  - You should see A and B markers on the timeline
  - Video should loop automatically between the two points
  - The segment is 15 seconds long

Good luck!
EOF

chown ga:ga /home/ga/Desktop/AB_LOOP_TASK.txt

# Launch VLC with RC interface enabled for state querying
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc \
    --avcodec-hw=none \
    --no-video-title-show \
    --extraintf rc \
    --rc-host localhost:9999 \
    /home/ga/Videos/research_interview.mp4 \
    > /tmp/vlc_ab_loop_task.log 2>&1 &"

# Wait for VLC to start
if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_ab_loop_task.log 2>/dev/null || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "✅ RC interface ready"
        break
    fi
    echo "RC interface not ready, waiting... ($i/10)"
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "✅ VLC window focused"
fi

# Give video time to start playing
sleep 2

# Pause the video so user can set up loop points
echo "Pausing video for loop setup..."
safe_xdotool ga :1 key space
sleep 0.5

# Seek to start to make it easier
echo "Seeking to beginning..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.5

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ A-B Repeat Loop Task Setup Complete"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "📝 INSTRUCTIONS:"
echo "  1. VLC is now paused at the start of the interview video"
echo "  2. Video duration: 60 seconds"
echo "  3. Target segment: 15 seconds to 30 seconds"
echo ""
echo "  TO SET A-B LOOP:"
echo "    a) Seek to 15 seconds (click timeline or use Shift+Right)"
echo "    b) Press Shift+L to set Point A"
echo "    c) Seek to 30 seconds"
echo "    d) Press Shift+L again to set Point B"
echo "    e) Video will loop the segment automatically"
echo ""
echo "  TIPS:"
echo "    - Look for A/B markers on the timeline"
echo "    - The video should replay the 15-30s segment continuously"
echo "    - Read /home/ga/Desktop/AB_LOOP_TASK.txt for detailed instructions"
echo ""
echo "═══════════════════════════════════════════════════════"