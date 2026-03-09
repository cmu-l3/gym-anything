#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure External Display Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure test video exists
TEST_VIDEO="/home/ga/Videos/sample_video.mp4"
if [ ! -f "$TEST_VIDEO" ]; then
    echo "ERROR: Test video not found: $TEST_VIDEO"
    exit 1
fi

# Reset VLC display configuration to defaults
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "Resetting VLC display configuration..."
    # Remove any existing display configuration lines
    sed -i '/^qt-fullscreen-screennumber=/d' "$VLC_RC"
    sed -i '/^qt-fullscreen-screenname=/d' "$VLC_RC"
    sed -i '/^fullscreen-screen=/d' "$VLC_RC"
    sed -i '/^vout-display=/d' "$VLC_RC"
    sed -i '/^x11-display=/d' "$VLC_RC"
    echo "Display configuration reset to defaults"
else
    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$VLC_RC")"
    chown -R ga:ga "$(dirname "$VLC_RC")"
    echo "VLC config directory created"
fi

# Create initial config state marker
cat > /tmp/vlc_display_initial_config.txt <<EOF
Initial VLC display configuration state
Reset at: $(date)
Config file: $VLC_RC
Expected change: qt-fullscreen-screennumber=1 (or equivalent)
EOF

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_display_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_display_task.log 2>/dev/null || true
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

# Wait for VLC to fully initialize
sleep 2

echo "=== Configure External Display Task Setup Complete ==="
echo ""
echo "📺 Scenario: You're a teacher connecting your laptop to a classroom projector."
echo "   The projector is your secondary display. You need VLC to show videos"
echo "   in fullscreen on the projector, not your laptop screen."
echo ""
echo "📝 Instructions:"
echo "  1. Open VLC Preferences (Tools → Preferences, or Ctrl+P)"
echo "  2. Click 'All' button at bottom-left to show all settings"
echo "  3. Navigate to: Video → Display (or Video → Fullscreen Settings)"
echo "  4. Find 'Fullscreen Video Device' or 'Fullscreen screen number'"
echo "  5. Set the value to 1 (secondary display/projector)"
echo "     - May be a dropdown, text field, or numeric input"
echo "  6. Click 'Save' button to apply changes"
echo "  7. Close preferences window"
echo ""
echo "💡 Hints:"
echo "  - Setting name may vary: 'screen number', 'device', or 'monitor'"
echo "  - Value should be 1 (for secondary display)"
echo "  - You can also edit ~/.config/vlc/vlcrc directly if familiar with configs"
echo ""
echo "🎯 Target setting: qt-fullscreen-screennumber=1"