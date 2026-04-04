#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Ambient Background Configuration Task ==="

kill_vlc ga
sleep 1

# Ensure Pictures directory exists for any screenshots
mkdir -p /home/ga/Pictures/vlc
chown -R ga:ga /home/ga/Pictures/vlc

# Reset VLC config to default state for ambient settings
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_CONFIG_DIR="/home/ga/.config/vlc"

# Ensure config directory exists
mkdir -p "$VLC_CONFIG_DIR"
chown -R ga:ga "$VLC_CONFIG_DIR"

if [ -f "$VLC_RC" ]; then
    # Reset specific settings to ensure clean starting state
    # Remove loop settings
    sed -i '/^loop=/d' "$VLC_RC"
    sed -i '/^repeat=/d' "$VLC_RC"
    sed -i '/^input-repeat=/d' "$VLC_RC"
    
    # Reset volume to default (100% = 256)
    sed -i 's/^audio-volume=.*/audio-volume=256/' "$VLC_RC"
    
    # Reset interface settings
    sed -i '/^qt-minimal-view=/d' "$VLC_RC"
    sed -i '/^qt-privacy-ask=/d' "$VLC_RC"
    sed -i '/^qt-system-tray=/d' "$VLC_RC"
    
    echo "VLC config reset to default ambient settings"
else
    # Create basic config file if it doesn't exist
    touch "$VLC_RC"
    chown ga:ga "$VLC_RC"
    echo "Created fresh VLC config file"
fi

# Create or verify ambient video exists
AMBIENT_VIDEO="/home/ga/Videos/forest_stream.mp4"

if [ ! -f "$AMBIENT_VIDEO" ]; then
    echo "Creating ambient nature video..."
    
    # Generate a 3-minute ambient video with audio using ffmpeg
    # Using color patterns and sine wave audio for ambient effect
    su - ga -c "cd /home/ga/Videos && ffmpeg -f lavfi -i 'color=c=0x2d5016:s=1280x720:d=180,format=yuv420p' \
        -f lavfi -i 'sine=frequency=220:duration=180,sine=frequency=330:duration=180' \
        -filter_complex '[0:v]drawtext=text=Forest Stream Ambiance:fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:alpha=0.7[v];[1:a][2:a]amix=inputs=2:duration=longest[a]' \
        -map '[v]' -map '[a]' -c:v libx264 -preset ultrafast -c:a aac -t 180 forest_stream.mp4 -y" 2>/dev/null || {
        
        # Fallback: use existing sample video if generation fails
        if [ -f "/home/ga/Videos/sample_video.mp4" ]; then
            echo "Using sample video as fallback"
            cp /home/ga/Videos/sample_video.mp4 "$AMBIENT_VIDEO"
        else
            echo "ERROR: Could not create or find ambient video"
            exit 1
        fi
    }
    
    chown ga:ga "$AMBIENT_VIDEO"
    echo "Ambient video ready: $AMBIENT_VIDEO"
else
    echo "Ambient video already exists: $AMBIENT_VIDEO"
fi

# Launch VLC with RC interface enabled
echo "Launching VLC with ambient video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 '$AMBIENT_VIDEO' > /tmp/vlc_ambient_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_ambient_task.log 2>/dev/null || true
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
        echo "RC interface ready"
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
    echo "VLC window focused"
fi

# Wait for VLC to fully render
sleep 2

echo "=== Ambient Background Configuration Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  Configure VLC for ambient background playback:"
echo ""
echo "  1. Enable Infinite Loop:"
echo "     - Use Playback → Loop (or press 'L' key)"
echo "     - OR: Tools → Preferences (Ctrl+P) → Show All → Playlist → Loop/Repeat"
echo ""
echo "  2. Set Volume to ~40%:"
echo "     - Use volume slider in interface"
echo "     - OR: Press Ctrl+Down multiple times to reduce to ~40%"
echo "     - Target: 35-45% range"
echo ""
echo "  3. Minimize Interface (optional but recommended):"
echo "     - View → Status Bar (uncheck to hide)"
echo "     - View → Advanced Controls (uncheck to hide)"
echo "     - OR: Tools → Preferences → Interface → Minimal interface"
echo ""
echo "  4. Save Settings:"
echo "     - Click 'Save' in Preferences if you opened it"
echo "     - Settings should auto-save when changed via menus"
echo ""
echo "  Current state:"
echo "  - Video: forest_stream.mp4 (3 min ambient loop)"
echo "  - Volume: 100% (needs adjustment to ~40%)"
echo "  - Loop: OFF (needs to be enabled)"
echo "  - Interface: FULL (can be minimized)"