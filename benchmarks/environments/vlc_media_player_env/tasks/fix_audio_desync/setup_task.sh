#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Audio Desync Task ==="

# Get target delay from environment or use default
TARGET_DELAY="${TARGET_DELAY_MS:-250}"

kill_vlc ga
sleep 1

# Ensure video directory exists
VIDEO_DIR="/home/ga/Videos"
mkdir -p "$VIDEO_DIR"
chown ga:ga "$VIDEO_DIR"

# Generate test video with sync markers if it doesn't exist
TEST_VIDEO="$VIDEO_DIR/desync_test.mp4"

if [ ! -f "$TEST_VIDEO" ]; then
    echo "Generating test video with audio/video sync markers..."
    
    # Create a 30-second video with visual and audio beep at specific timestamps
    # This helps users verify sync by matching visual flash with audio beep
    su - ga -c "ffmpeg -f lavfi -i 'color=c=black:s=1280x720:d=30:r=30' \
        -f lavfi -i 'sine=frequency=1000:duration=0.2,aresample=44100,apad=pad_dur=0.8,concat=n=30:v=0:a=1' \
        -vf \"drawtext=text='SYNC TEST':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2.9,3.1)+between(t,9.9,10.1)+between(t,19.9,20.1)',\
             drawtext=text='Listen for beep at 3s, 10s, 20s':fontsize=24:fontcolor=yellow:x=(w-text_w)/2:y=100\" \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
        -c:a aac -shortest \
        '$TEST_VIDEO' -y 2>/tmp/video_generation.log" || {
        echo "ERROR: Failed to generate test video"
        cat /tmp/video_generation.log
        
        # Fallback: use existing sample video if generation fails
        if [ -f "$VIDEO_DIR/sample_video.mp4" ]; then
            echo "Using existing sample video as fallback"
            cp "$VIDEO_DIR/sample_video.mp4" "$TEST_VIDEO"
        else
            echo "ERROR: No fallback video available"
            exit 1
        fi
    }
    
    chown ga:ga "$TEST_VIDEO"
    echo "✓ Test video created: $TEST_VIDEO"
fi

# Reset VLC audio-desync setting to 0 (no offset)
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p "$(dirname "$VLC_RC")"

# Remove any existing audio-desync settings
if [ -f "$VLC_RC" ]; then
    sed -i '/^audio-desync=/d' "$VLC_RC"
    sed -i '/^#audio-desync=/d' "$VLC_RC"
fi

# Set default audio-desync to 0
echo "audio-desync=0" >> "$VLC_RC"
chown ga:ga "$VLC_RC"

echo "Audio-desync reset to 0ms"

# Launch VLC with test video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$TEST_VIDEO' > /tmp/vlc_desync_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_desync_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for VLC to fully initialize
sleep 2

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Create task instruction file for reference
cat > /tmp/task_instruction.txt <<EOF
╔════════════════════════════════════════════════════════════╗
║           TASK: Fix Audio Desynchronization               ║
╚════════════════════════════════════════════════════════════╝

PROBLEM:
The video has audio that is out of sync with the video.

YOUR GOAL:
Adjust VLC's audio delay setting to: ${TARGET_DELAY}ms

METHODS TO ADJUST:

Method 1 - Menu (Recommended):
  1. Go to: Tools → Track Synchronization
  2. In the "Synchronization" tab
  3. Find "Audio track synchronization" field
  4. Enter: ${TARGET_DELAY} (in milliseconds)
  5. Click "Close" to apply (NOT Cancel!)

Method 2 - Keyboard Shortcuts:
  • Press 'J' to delay audio (increase value)
  • Press 'K' to advance audio (decrease value)
  • Each press adjusts by 50ms

UNDERSTANDING THE VALUES:
  • Positive (+250ms): Audio plays 250ms LATER than video
    → Use when audio is AHEAD of video (lips move before sound)
  
  • Negative (-250ms): Audio plays 250ms EARLIER than video  
    → Use when audio is BEHIND video (sound before lips move)

TESTING:
  Watch the video - you'll see visual flashes and hear beeps
  at 3s, 10s, and 20s. They should be synchronized after
  your adjustment.

Current target: ${TARGET_DELAY}ms
Tolerance: ±50ms

═══════════════════════════════════════════════════════════
EOF

cat /tmp/task_instruction.txt

echo "=== Fix Audio Desync Task Setup Complete ==="
echo "📝 Target audio delay: ${TARGET_DELAY}ms"
echo "📝 Current setting: 0ms (no offset)"
echo "📝 VLC is now playing the test video in a loop"