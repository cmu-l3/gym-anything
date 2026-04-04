#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Capture Desktop Lecture Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Kill any existing gedit instances
pkill -f gedit 2>/dev/null || true
sleep 0.5

# Create a visible target window with content for the capture
echo "Creating visible desktop content for capture..."

# Create a simple document with large, visible text
cat > /tmp/capture_target.txt <<'EOF'
═══════════════════════════════════════════
    DESKTOP CAPTURE TEST DOCUMENT
═══════════════════════════════════════════

This window serves as visible content for
the desktop recording test.

Key Topics:
• Screen Capture Fundamentals
• Video Recording Techniques  
• Documentation Methods
• Lecture Preservation

Time: $(date)

This content verifies the desktop recording
is capturing actual screen output.

═══════════════════════════════════════════
EOF

# Launch gedit with the target document in background
su - ga -c "DISPLAY=:1 gedit /tmp/capture_target.txt > /tmp/gedit.log 2>&1 &"
sleep 2

# Wait for gedit window to appear
if ! wait_for_window "gedit" 10; then
    echo "WARNING: gedit window did not appear, but continuing"
fi

# Maximize gedit window so it's clearly visible in capture
GEDIT_WID=$(su - ga -c "DISPLAY=:1 xdotool search --name 'gedit' | head -1" || echo "")
if [ -n "$GEDIT_WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -r $GEDIT_WID -b add,maximized_vert,maximized_horz" || true
    sleep 1
fi

# Ensure output directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Desktop  
mkdir -p /home/ga/Pictures
chown -R ga:ga /home/ga/Videos /home/ga/Desktop /home/ga/Pictures

# Launch VLC in clean state (no video loaded)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_capture_task.log 2>&1 &"

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

# Record start time for later verification
date +%s > /tmp/vlc_capture_start_time.txt

echo "=== Capture Desktop Lecture Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. A target window (gedit) is visible on the desktop"
echo "  2. VLC is now open and ready"
echo "  3. Navigate to: Media → Open Capture Device (or Ctrl+C)"
echo "  4. In 'Capture mode' dropdown, select 'Desktop'"
echo "  5. Set 'Desired frame rate' to 10-15 fps"
echo "  6. Click the dropdown next to 'Play' and select 'Play' (or just click Play)"
echo "  7. Click the Record button (red circle) in playback controls"
echo "  8. Wait 10-15 seconds"
echo "  9. Click Record button again to stop"
echo "  10. Recording will be saved to Videos directory"