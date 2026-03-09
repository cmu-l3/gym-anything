#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Shuffle No Repeat Task ==="

kill_vlc ga
sleep 1

# Create ambient videos directory
AMBIENT_DIR="/home/ga/Videos/ambient"
mkdir -p "$AMBIENT_DIR"
chown ga:ga "$AMBIENT_DIR"

echo "Generating 10 sample ambient videos..."

# Generate 10 short ambient-style videos with different colors/patterns
# Each video is ~5 seconds long for quick testing
for i in $(seq -w 1 10); do
    VIDEO_FILE="$AMBIENT_DIR/ambient_ocean_${i}.mp4"
    
    if [ ! -f "$VIDEO_FILE" ]; then
        # Generate unique color for each video (different hue)
        HUE=$((i * 36))  # 0, 36, 72, ... 324 degrees
        
        # Create video with colored pattern
        ffmpeg -f lavfi -i "color=c=0x$(printf '%02x%02x%02x' $((128 + i * 10)) $((100 + i * 5)) $((150 - i * 5))):s=640x480:d=5" \
            -f lavfi -i "sine=frequency=440:duration=5" \
            -c:v libx264 -preset ultrafast -c:a aac -shortest \
            "$VIDEO_FILE" -y >/dev/null 2>&1
        
        chown ga:ga "$VIDEO_FILE"
        echo "  Created: ambient_ocean_${i}.mp4"
    fi
done

echo "✅ Created 10 ambient videos in $AMBIENT_DIR"

# Reset VLC config to ensure clean state
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove shuffle/repeat settings to start fresh
    sed -i '/^random=/d' "$VLC_RC"
    sed -i '/^loop=/d' "$VLC_RC"
    sed -i '/^repeat=/d' "$VLC_RC"
    echo "VLC playback settings reset"
fi

# Clear any existing playlists
VLC_PLAYLIST_DIR="/home/ga/.local/share/vlc"
rm -f "$VLC_PLAYLIST_DIR"/*.xspf 2>/dev/null || true

# Launch VLC with RC interface
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 > /tmp/vlc_shuffle_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Give VLC time to fully initialize
sleep 2

echo "=== Configure Shuffle No Repeat Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Add all videos from ~/Videos/ambient/ to VLC"
echo "     - Use Media → Open Folder"
echo "     - Select /home/ga/Videos/ambient/"
echo "  2. Enable shuffle mode:"
echo "     - Click shuffle button in controls (crossed arrows icon)"
echo "     - OR: Playback → Random"
echo "  3. Enable repeat-all mode:"
echo "     - Click repeat button until it shows loop icon"
echo "     - OR: Playback → Repeat All"
echo "  4. Ensure playback starts (videos should play continuously in random order)"