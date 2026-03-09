#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Projector Output Task ==="

TASK_NAME="configure_projector_output"

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/.config/vlc

# Generate a sample 1920x1080 video for testing if it doesn't exist
VIDEO_FILE="/home/ga/Videos/presentation_video.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "[$TASK_NAME] Generating sample 1080p presentation video..."
    
    # Try to generate a test pattern video
    if command -v ffmpeg &> /dev/null; then
        ffmpeg -f lavfi -i testsrc=duration=20:size=1920x1080:rate=30 \
               -f lavfi -i sine=frequency=1000:duration=20 \
               -c:v libx264 -preset ultrafast -crf 23 \
               -c:a aac -b:a 128k \
               "$VIDEO_FILE" \
               -y 2>&1 | tee /tmp/video_gen.log || {
            echo "[$TASK_NAME] Warning: Could not generate test pattern, creating simple video..."
            # Fallback: create a minimal video
            ffmpeg -f lavfi -i color=c=blue:s=1920x1080:d=10 \
                   -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
                   -c:v libx264 -preset ultrafast -t 10 \
                   -c:a aac \
                   "$VIDEO_FILE" -y 2>&1 || echo "[$TASK_NAME] Warning: Video generation had issues"
        }
    else
        echo "[$TASK_NAME] ERROR: ffmpeg not available, cannot generate video"
        # Try to use existing sample video as fallback
        if [ -f "/home/ga/Videos/sample_video.mp4" ]; then
            cp /home/ga/Videos/sample_video.mp4 "$VIDEO_FILE"
            echo "[$TASK_NAME] Using existing sample video as fallback"
        fi
    fi
fi

# Verify video exists
if [ ! -f "$VIDEO_FILE" ]; then
    echo "[$TASK_NAME] ERROR: Presentation video not found: $VIDEO_FILE"
    exit 1
fi

# Reset VLC configuration to default (remove any existing video output settings)
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_CONFIG" ]; then
    echo "[$TASK_NAME] Cleaning existing VLC configuration..."
    # Remove any existing video output resolution settings
    sed -i '/^width=/d' "$VLC_CONFIG"
    sed -i '/^height=/d' "$VLC_CONFIG"
    sed -i '/^video-width=/d' "$VLC_CONFIG"
    sed -i '/^video-height=/d' "$VLC_CONFIG"
    sed -i '/^vout-width=/d' "$VLC_CONFIG"
    sed -i '/^vout-height=/d' "$VLC_CONFIG"
    sed -i '/^qt-video-width=/d' "$VLC_CONFIG"
    sed -i '/^qt-video-height=/d' "$VLC_CONFIG"
    sed -i '/^x11-display-width=/d' "$VLC_CONFIG"
    sed -i '/^x11-display-height=/d' "$VLC_CONFIG"
    echo "[$TASK_NAME] Cleaned video output settings from config"
fi

# Ensure VLC config exists (create minimal config if needed)
if [ ! -f "$VLC_CONFIG" ]; then
    echo "[$TASK_NAME] Creating minimal VLC configuration..."
    cat > "$VLC_CONFIG" << 'EOF'
# VLC media player configuration
[qt]
qt-privacy-ask=0

[core]
metadata-network-access=0
EOF
fi

# Set proper permissions
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/.config/vlc

# Launch VLC without the video initially (so agent can configure first)
echo "[$TASK_NAME] Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_projector_config_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "[$TASK_NAME] ERROR: VLC failed to start"
    cat /tmp/vlc_projector_config_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "[$TASK_NAME] ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "[$TASK_NAME] Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
echo "[$TASK_NAME] Focusing VLC window..."
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Configure Projector Output Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Target resolution: 1280x800 (WXGA projector)"
echo "  Source video: $VIDEO_FILE (1920x1080)"
echo ""
echo "  Suggested approach:"
echo "  1. Open Preferences (Tools → Preferences or Ctrl+P)"
echo "  2. Click 'All' at bottom left to show advanced settings"
echo "  3. Navigate to Video → Output modules"
echo "  4. Configure video output window size:"
echo "     - Look for 'Window properties' or 'Video width' settings"
echo "     - Set width to 1280"
echo "     - Set height to 800"
echo "  5. Save preferences"
echo ""
echo "  Alternative: Edit config file directly"
echo "     Config location: /home/ga/.config/vlc/vlcrc"
echo "     Add: qt-video-width=1280"
echo "     Add: qt-video-height=800"