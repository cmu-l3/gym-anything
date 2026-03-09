#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Elderly-Friendly Viewing Task ==="

kill_vlc ga
sleep 1

# Reset VLC config to defaults (ensure clean slate)
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_CONFIG_DIR="/home/ga/.config/vlc"

# Backup existing config if it exists
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "${VLC_RC}.backup"
    echo "Backed up existing VLC config"
fi

# Reset to defaults by removing customizations
if [ -f "$VLC_RC" ]; then
    # Remove elderly-friendly settings to ensure clean slate
    sed -i '/^freetype-fontsize=/d' "$VLC_RC"
    sed -i '/^freetype-rel-fontsize=/d' "$VLC_RC"
    sed -i '/^freetype-bold=/d' "$VLC_RC"
    sed -i '/^norm-max-level=/d' "$VLC_RC"
    sed -i '/^audio-replay-gain-mode=/d' "$VLC_RC"
    sed -i '/^audio-compressor=/d' "$VLC_RC"
    sed -i '/^compressor-ratio=/d' "$VLC_RC"
    sed -i '/^qt-minimal-view=/d' "$VLC_RC"
    sed -i '/^qt-privacy-ask=/d' "$VLC_RC"
    sed -i '/^qt-updates-notif=/d' "$VLC_RC"
    echo "Reset VLC config to defaults"
fi

# Ensure directories exist
mkdir -p /home/ga/Videos/elderly_test
mkdir -p /home/ga/Videos/subtitles
chown -R ga:ga /home/ga/Videos/elderly_test
chown -R ga:ga /home/ga/Videos/subtitles

# Generate test videos with varying audio levels
echo "Generating test videos with varying audio levels..."

# Quiet video (audio at 30% volume)
if [ ! -f /home/ga/Videos/elderly_test/quiet_video.mp4 ]; then
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
      -f lavfi -i sine=frequency=440:duration=10 \
      -filter_complex "[1:a]volume=0.3[a]" -map 0:v -map "[a]" \
      -c:v libx264 -preset ultrafast -c:a aac \
      -y /home/ga/Videos/elderly_test/quiet_video.mp4 2>/dev/null
    echo "Created quiet_video.mp4"
fi

# Loud video (audio at 150% volume)
if [ ! -f /home/ga/Videos/elderly_test/loud_video.mp4 ]; then
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
      -f lavfi -i sine=frequency=880:duration=10 \
      -filter_complex "[1:a]volume=1.5[a]" -map 0:v -map "[a]" \
      -c:v libx264 -preset ultrafast -c:a aac \
      -y /home/ga/Videos/elderly_test/loud_video.mp4 2>/dev/null
    echo "Created loud_video.mp4"
fi

# Normal video (audio at 100%)
if [ ! -f /home/ga/Videos/elderly_test/normal_video.mp4 ]; then
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
      -f lavfi -i sine=frequency=660:duration=10 \
      -c:v libx264 -preset ultrafast -c:a aac \
      -y /home/ga/Videos/elderly_test/normal_video.mp4 2>/dev/null
    echo "Created normal_video.mp4"
fi

chown -R ga:ga /home/ga/Videos/elderly_test

# Create test subtitle file with timing
cat > /home/ga/Videos/subtitles/elderly_test.srt << 'EOF'
1
00:00:01,000 --> 00:00:04,000
Welcome to the family video.
These subtitles need to be large and clear.

2
00:00:05,000 --> 00:00:08,000
Important dialogue should be easy to read
even from across the room.

3
00:00:09,000 --> 00:00:12,000
Volume should stay consistent
between different videos.
EOF

chown ga:ga /home/ga/Videos/subtitles/elderly_test.srt
echo "Created test subtitle file"

# Launch VLC with a test video
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop /home/ga/Videos/elderly_test/normal_video.mp4 > /tmp/vlc_elderly_task.log 2>&1 &"

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

sleep 2

echo "=== Configure Elderly-Friendly Viewing Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "Configure VLC for an elderly user (78 years old) with the following needs:"
echo ""
echo "1. SUBTITLE SIZE - Make subtitles MUCH larger (3x default):"
echo "   Tools → Preferences → Subtitles/OSD → Text renderer"
echo "   - Font size: ≥72 points (or relative size ≥40)"
echo "   - Enable Bold for better visibility"
echo ""
echo "2. AUDIO NORMALIZATION - Prevent volume jumps between videos:"
echo "   Tools → Preferences → Show All → Audio"
echo "   - Enable 'Normalize volume' or 'ReplayGain mode'"
echo ""
echo "3. AUDIO COMPRESSION - Make dialogue clearer (night mode):"
echo "   Tools → Preferences → Show All → Audio → Filters"
echo "   - Enable Dynamic range compressor"
echo ""
echo "4. SIMPLIFY INTERFACE - Reduce confusion:"
echo "   Tools → Preferences → Interface"
echo "   - Enable minimal view or simple interface"
echo ""
echo "5. DISABLE PROMPTS - Stop confusing dialogs:"
echo "   Tools → Preferences → Interface"
echo "   - Disable privacy prompts"
echo "   - Disable update notifications"
echo ""
echo "Test videos available at: /home/ga/Videos/elderly_test/"
echo "Test subtitles at: /home/ga/Videos/subtitles/elderly_test.srt"
echo ""
echo "⚠️  Close preferences dialog and VLC to save settings!"