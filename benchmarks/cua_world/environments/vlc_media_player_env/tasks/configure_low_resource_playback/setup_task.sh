#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Low Resource Playback Task ==="

kill_vlc ga
sleep 1

# Create 1080p test video if it doesn't exist
TEST_VIDEO="/home/ga/Videos/test_1080p.mp4"
if [ ! -f "$TEST_VIDEO" ]; then
    echo "Generating 1080p test video..."
    # Generate 30-second 1080p test video with color bars and timestamp
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=30:size=1920x1080:rate=30 -f lavfi -i sine=frequency=1000:duration=30 -pix_fmt yuv420p -c:v libx264 -preset ultrafast -c:a aac '$TEST_VIDEO' -y > /tmp/ffmpeg_gen.log 2>&1"
    
    if [ ! -f "$TEST_VIDEO" ]; then
        echo "ERROR: Failed to generate test video"
        cat /tmp/ffmpeg_gen.log
        exit 1
    fi
    echo "✅ Test video generated: $TEST_VIDEO"
fi

# Reset VLC config to defaults (remove performance optimizations)
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_DIR="/home/ga/.config/vlc"

# Backup existing config if present
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "${VLC_RC}.backup"
    echo "Backed up existing VLC config"
fi

# Reset to default settings by removing performance-related keys
if [ -f "$VLC_RC" ]; then
    echo "Resetting VLC performance settings to defaults..."
    
    # Remove hardware acceleration settings
    sed -i '/^avcodec-hw=/d' "$VLC_RC"
    
    # Remove frame skipping settings
    sed -i '/^skip-frames=/d' "$VLC_RC"
    sed -i '/^skip-late-videoframes=/d' "$VLC_RC"
    
    # Remove video output settings
    sed -i '/^vout=/d' "$VLC_RC"
    
    # Remove cache settings (set to default high value)
    sed -i '/^file-caching=/d' "$VLC_RC"
    echo "file-caching=1000" >> "$VLC_RC"
    
    # Remove filter settings
    sed -i '/^video-filter=/d' "$VLC_RC"
    
    # Remove deinterlace settings
    sed -i '/^deinterlace=/d' "$VLC_RC"
    sed -i '/^deinterlace-mode=/d' "$VLC_RC"
    
    echo "✅ VLC config reset to defaults"
else
    echo "⚠️ VLC config file not found, will be created on first launch"
fi

# Launch VLC with test video (no hardware acceleration to simulate constrained system)
echo "Launching VLC with 1080p test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$TEST_VIDEO' > /tmp/vlc_lowres_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_lowres_task.log
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

# Wait for VLC to fully initialize
sleep 2

echo "=== Configure Low Resource Playback Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a 1080p video (may stutter on default settings)"
echo "  2. Open Preferences: Tools -> Preferences (Ctrl+P)"
echo "  3. Switch to 'All' settings mode (radio button at bottom left)"
echo "  4. Navigate to Input/Codecs section:"
echo "     - Set 'Hardware-accelerated decoding' to 'Automatic' or 'any'"
echo "     - Enable 'Skip frames' checkbox"
echo "  5. Navigate to Video section:"
echo "     - Set 'Output' to lightweight module (e.g., 'X11 video output')"
echo "  6. Navigate to Input/Codecs -> Advanced:"
echo "     - Set 'File caching' to 300 (reduced from 1000)"
echo "  7. Ensure Video -> Filters: No filters enabled"
echo "  8. Click 'Save' button"
echo "  9. Restart may be required for some settings"
echo ""
echo "💡 Most important: Enable hardware acceleration!"