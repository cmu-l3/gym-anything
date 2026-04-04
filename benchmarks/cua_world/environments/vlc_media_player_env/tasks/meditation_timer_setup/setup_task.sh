#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Meditation Timer Setup Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create video directory if needed
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate a 45-minute meditation video (nature scene with calming audio)
MEDITATION_VIDEO="/home/ga/Videos/nature_meditation.mp4"

if [ ! -f "$MEDITATION_VIDEO" ]; then
    echo "Generating 45-minute meditation video..."
    
    # Create a 45-minute (2700 seconds) video with peaceful content
    # Using a simple gradient/color test pattern with 432 Hz sine wave (meditation frequency)
    # Note: For faster generation, we use a lower resolution and frame rate
    su - ga -c "ffmpeg -f lavfi -i 'color=c=0x1e4d2b:s=1280x720:d=2700,format=rgb24' \
        -f lavfi -i 'sine=frequency=432:duration=2700:sample_rate=48000' \
        -c:v libx264 -preset ultrafast -tune stillimage -crf 28 \
        -c:a aac -b:a 128k \
        -y '$MEDITATION_VIDEO' > /tmp/ffmpeg_meditation.log 2>&1" || {
        
        # Fallback: Create a shorter test video if full generation fails
        echo "⚠️ Full video generation failed, creating shorter test video..."
        su - ga -c "ffmpeg -f lavfi -i 'color=c=0x1e4d2b:s=640x480:d=2700' \
            -f lavfi -i 'sine=frequency=432:duration=2700' \
            -c:v libx264 -preset ultrafast -tune stillimage -crf 30 \
            -c:a aac -b:a 96k \
            -y '$MEDITATION_VIDEO' > /tmp/ffmpeg_meditation_fallback.log 2>&1" || {
            
            # Final fallback: Copy existing sample if available
            if [ -f /home/ga/Videos/sample_video.mp4 ]; then
                echo "Using existing sample video as fallback"
                cp /home/ga/Videos/sample_video.mp4 "$MEDITATION_VIDEO"
            else
                echo "ERROR: Cannot create meditation video"
                exit 1
            fi
        }
    }
    
    chown ga:ga "$MEDITATION_VIDEO"
    echo "✅ Meditation video ready: $(ls -lh $MEDITATION_VIDEO | awk '{print $5}')"
fi

# Verify video exists and is valid
if [ ! -f "$MEDITATION_VIDEO" ]; then
    echo "ERROR: Meditation video not found: $MEDITATION_VIDEO"
    exit 1
fi

# Clear bash history to ensure clean detection of new commands
su - ga -c "> ~/.bash_history"
history -c 2>/dev/null || true

# Reset VLC config to default (no timer settings)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    sed -i '/^run-time=/d' "$VLC_RC"
    sed -i '/^stop-time=/d' "$VLC_RC"
    sed -i '/^play-and-exit=/d' "$VLC_RC"
    echo "VLC config reset (timer settings removed)"
fi

# Launch VLC without timer (agent needs to configure it)
echo "Launching VLC (without timer configured)..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_meditation_task.log 2>&1 &"

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

echo "=== Meditation Timer Setup Task Complete ==="
echo "📝 Instructions:"
echo "  1. Configure VLC to automatically quit after 30 minutes (1800 seconds)"
echo "  2. Video file: /home/ga/Videos/nature_meditation.mp4"
echo "  3. Methods:"
echo "     - Close VLC and relaunch with: vlc --run-time=1800 --play-and-exit <video>"
echo "     - Or use: vlc --stop-time=1800 <video>"
echo "  4. Test that VLC will auto-quit after the specified time"
echo "  5. 30 minutes = 1800 seconds"