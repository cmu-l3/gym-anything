#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Buffer for Network Task ==="

kill_vlc ga
sleep 1

# Create task directory for large test file
TASK_DIR="/home/ga/Videos/network_buffer_test"
mkdir -p "$TASK_DIR"
chown ga:ga "$TASK_DIR"

# Use existing sample video or generate one
VIDEO_FILE="$TASK_DIR/large_network_file.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "Generating large test video file (simulating network storage footage)..."
    # Generate a 60-second high-bitrate video to simulate 4K footage
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=60:size=1920x1080:rate=30 \
        -f lavfi -i sine=frequency=440:duration=60 \
        -c:v libx264 -preset ultrafast -b:v 40M -maxrate 40M -bufsize 80M \
        -c:a aac -b:a 192k \
        -y '$VIDEO_FILE' 2>&1" | head -20
    
    if [ ! -f "$VIDEO_FILE" ]; then
        echo "WARNING: Could not generate test video, using existing sample"
        VIDEO_FILE="/home/ga/Videos/sample_video.mp4"
    else
        FILE_SIZE=$(du -h "$VIDEO_FILE" | cut -f1)
        echo "✅ Generated test file: $VIDEO_FILE (${FILE_SIZE})"
    fi
else
    echo "Test file already exists: $VIDEO_FILE"
fi

# Reset VLC config to default cache settings
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p "/home/ga/.config/vlc"
chown -R ga:ga "/home/ga/.config/vlc"

echo "Resetting VLC cache settings to defaults..."

# Backup existing config if present
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "${VLC_RC}.backup.$(date +%s)"
    echo "Backed up existing config"
fi

# Remove any existing cache settings and reset to defaults
if [ -f "$VLC_RC" ]; then
    sed -i '/^file-caching=/d' "$VLC_RC"
    sed -i '/^network-caching=/d' "$VLC_RC"
    sed -i '/^disc-caching=/d' "$VLC_RC"
    sed -i '/^live-caching=/d' "$VLC_RC"
fi

# Ensure we have a vlcrc file with default settings
if [ ! -f "$VLC_RC" ] || ! grep -q "\[core\]" "$VLC_RC"; then
    cat > "$VLC_RC" << 'EOF'
[core]
# Default file caching (300ms) - too small for network files
file-caching=300

# Network caching defaults
network-caching=1000

# Other defaults
disc-caching=300
live-caching=300

[qt]
qt-privacy-ask=0
qt-start-minimized=0
EOF
    chown ga:ga "$VLC_RC"
    echo "Created vlcrc with default cache settings"
else
    # Ensure file-caching is set to default 300
    if ! grep -q "^file-caching=" "$VLC_RC"; then
        sed -i '/\[core\]/a file-caching=300' "$VLC_RC"
    else
        sed -i 's/^file-caching=.*/file-caching=300/' "$VLC_RC"
    fi
    echo "Reset file-caching to default (300ms)"
fi

# Verify the reset worked
CURRENT_CACHE=$(grep "^file-caching=" "$VLC_RC" | cut -d= -f2 || echo "300")
echo "Current file-caching value: ${CURRENT_CACHE}ms"

# Create instruction file
cat > "$TASK_DIR/INSTRUCTIONS.txt" << 'EOF'
NETWORK BUFFER CONFIGURATION TASK
==================================

SCENARIO:
You have large video files stored on network storage (NAS/cloud).
VLC's default cache (300ms) causes stuttering during playback.

YOUR TASK:
Configure VLC to increase file caching to at least 3000ms (3 seconds).

METHOD 1 - GUI (Recommended):
1. Open VLC (if not already open)
2. Go to: Tools → Preferences (Ctrl+P)
3. Click "Show settings: All" (bottom-left)
4. Navigate to: Input / Codecs → Advanced
5. Find "File caching (ms)" setting
6. Change value from 300 to 3000 (or higher, max 60000)
7. Click "Save" button
8. Close and restart VLC for changes to take effect

METHOD 2 - Config File:
1. Edit: ~/.config/vlc/vlcrc
2. Find line: file-caching=300
3. Change to: file-caching=3000
4. Save file
5. Restart VLC

TEST FILE:
/home/ga/Videos/network_buffer_test/large_network_file.mp4

VERIFICATION:
Your configuration will be checked automatically.
EOF

chown ga:ga "$TASK_DIR/INSTRUCTIONS.txt"

# Launch VLC with the test video
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$VIDEO_FILE' > /tmp/vlc_buffer_config_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_buffer_config_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo ""
echo "=== Configure Buffer for Network Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SCENARIO: Large video files on network storage are"
echo "           stuttering. Default VLC cache too small."
echo ""
echo "  GOAL: Increase file caching from 300ms to 3000ms+"
echo ""
echo "  METHOD 1 (GUI):"
echo "    1. Tools → Preferences (Ctrl+P)"
echo "    2. Show settings: All (bottom-left)"
echo "    3. Input/Codecs → Advanced → File caching (ms)"
echo "    4. Change 300 → 3000"
echo "    5. Save"
echo ""
echo "  METHOD 2 (File):"
echo "    Edit ~/.config/vlc/vlcrc"
echo "    Change: file-caching=3000"
echo ""
echo "  Current setting: ${CURRENT_CACHE}ms (default)"
echo "  Target: 3000ms - 60000ms"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""