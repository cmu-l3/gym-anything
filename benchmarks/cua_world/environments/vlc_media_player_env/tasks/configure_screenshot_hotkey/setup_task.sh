#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Screenshot Hotkey Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure VLC config directory exists
VLC_CONFIG_DIR="/home/ga/.config/vlc"
mkdir -p "$VLC_CONFIG_DIR"
chown -R ga:ga "$VLC_CONFIG_DIR"

# Reset snapshot hotkey to default in vlcrc to ensure consistent starting state
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Resetting snapshot hotkey to default..."
    # Remove any existing snapshot hotkey settings
    sed -i '/^key-snapshot=/d' "$VLC_RC"
    sed -i '/^global-key-snapshot=/d' "$VLC_RC"
    
    # Set to default value (Shift+s)
    echo "key-snapshot=Shift+s" >> "$VLC_RC"
    
    echo "Hotkey reset to default (Shift+s)"
else
    echo "Creating new vlcrc with default snapshot hotkey..."
    cat > "$VLC_RC" <<EOF
# VLC configuration file
[qt]
qt-privacy-ask=0

[core]
key-snapshot=Shift+s
EOF
    chown ga:ga "$VLC_RC"
fi

# Launch VLC with a sample video to provide context
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show /home/ga/Videos/sample_video.mp4 > /tmp/vlc_hotkey_task.log 2>&1 &"

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

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for VLC to fully initialize
sleep 2

echo "=== Configure Screenshot Hotkey Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open VLC Preferences: Tools → Preferences (or Ctrl+P)"
echo "  2. Click 'Show settings: All' button at bottom-left"
echo "  3. Navigate to: Interface → Hotkeys settings"
echo "  4. Scroll to find 'Take video snapshot' hotkey"
echo "  5. Click on the hotkey field (currently: Shift+s)"
echo "  6. Press a new convenient key (e.g., F8, Ctrl+P, or another key)"
echo "  7. Click 'Save' button at bottom to apply changes"
echo ""
echo "Current hotkey: Shift+s (default)"
echo "Suggested alternatives: F8, F9, F11, Ctrl+P, Alt+S"