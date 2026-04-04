#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Clear Media History Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure video files exist for populating history
VIDEO_DIR="/home/ga/Videos"
mkdir -p "$VIDEO_DIR"

# Create a backup of existing VLC config
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_QT_CONF="$VLC_CONFIG_DIR/vlc-qt-interface.conf"
mkdir -p "$VLC_CONFIG_DIR"
chown -R ga:ga "$VLC_CONFIG_DIR"

# Record initial state
echo "Preparing to populate recent media history..."

# Populate recent history by opening multiple videos
VIDEOS=(
    "/home/ga/Videos/sample_video.mp4"
    "/home/ga/Videos/color_test.mp4"
    "/home/ga/Videos/sample_audio.mp3"
)

# Check if media files exist
for video in "${VIDEOS[@]}"; do
    if [ ! -f "$video" ]; then
        echo "WARNING: Media file not found: $video"
    fi
done

echo "Opening videos to populate recent history..."

# Open each video briefly to add to recent history
for i in "${!VIDEOS[@]}"; do
    video="${VIDEOS[$i]}"
    
    if [ ! -f "$video" ]; then
        continue
    fi
    
    echo "Opening: $video"
    
    # Launch VLC with the video
    su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show '$video' > /tmp/vlc_history_populate_${i}.log 2>&1 &"
    
    # Wait for VLC to start
    if ! wait_for_process "vlc" 10; then
        echo "WARNING: VLC failed to start for $video"
        continue
    fi
    
    # Let it play briefly to register in history
    sleep 2
    
    # Close VLC
    kill_vlc ga
    sleep 1
done

echo "Recent history populated. Verifying..."

# Check if recent items were added
if [ -f "$VLC_QT_CONF" ]; then
    RECENT_COUNT=$(grep -c "file://" "$VLC_QT_CONF" 2>/dev/null || echo "0")
    echo "Recent items in config: $RECENT_COUNT"
    
    # Save initial count for verification
    echo "$RECENT_COUNT" > /tmp/vlc_history_initial_count.txt
else
    echo "WARNING: VLC config not found, history may not be populated"
    echo "0" > /tmp/vlc_history_initial_count.txt
fi

# Launch VLC for the task (without any file)
echo "Launching VLC for task..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_history_task.log 2>&1 &"

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

echo "=== Clear Media History Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC has recent media history from previous viewing"
echo "  2. Clear all recent items using one of these methods:"
echo ""
echo "  Method A (Recommended - More thorough):"
echo "    a. Press Ctrl+P to open Preferences"
echo "    b. Look for 'Privacy' or 'Interface' settings"
echo "    c. Find 'Clear' button for recent items"
echo "    d. Click 'Clear' then 'Save'"
echo ""
echo "  Method B (Quick):"
echo "    a. Click Media → Open Recent"
echo "    b. Click 'Clear' at bottom of menu"
echo ""
echo "  Goal: Make Media → Open Recent menu empty"