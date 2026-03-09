#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Enable HDR Tone Mapping Task ==="

kill_vlc ga
sleep 1

# Ensure Videos directory exists
VIDEO_DIR="/home/ga/Videos"
mkdir -p "$VIDEO_DIR"
chown ga:ga "$VIDEO_DIR"

# Generate HDR test video with HDR10 metadata
echo "Generating HDR test video with HDR10 metadata..."
HDR_VIDEO="$VIDEO_DIR/hdr_test_vacation.mp4"

# Check if ffmpeg supports required features
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found"
    exit 1
fi

# Create HDR test video with color bars and HDR metadata
# Using BT.2020 color primaries and SMPTE 2084 (PQ) transfer for HDR10
su - ga -c "ffmpeg -f lavfi -i testsrc2=duration=20:size=1920x1080:rate=30 \
    -f lavfi -i sine=frequency=440:duration=20 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p10le \
    -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
    -x264-params \"colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc\" \
    -c:a aac -b:a 128k -shortest \
    \"$HDR_VIDEO\" -y 2>/tmp/hdr_gen.log" || {
    echo "⚠️ Full HDR encoding failed, trying simpler approach..."
    # Fallback: Create video with just BT.2020 color space (simpler HDR indicator)
    su - ga -c "ffmpeg -f lavfi -i testsrc2=duration=20:size=1920x1080:rate=30 \
        -f lavfi -i sine=frequency=440:duration=20 \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
        -color_primaries bt2020 -color_trc bt2020-10 -colorspace bt2020nc \
        -c:a aac -b:a 128k -shortest \
        \"$HDR_VIDEO\" -y 2>/tmp/hdr_gen_fallback.log"
}

if [ ! -f "$HDR_VIDEO" ]; then
    echo "ERROR: Failed to generate HDR test video"
    cat /tmp/hdr_gen.log 2>/dev/null || cat /tmp/hdr_gen_fallback.log 2>/dev/null || true
    exit 1
fi

echo "✅ HDR test video created: $HDR_VIDEO"
ls -lh "$HDR_VIDEO"

# Reset VLC preferences to defaults (disable any existing tone mapping)
echo "Resetting VLC preferences to disable tone mapping..."
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

mkdir -p "$VLC_CONFIG_DIR"
chown -R ga:ga "$VLC_CONFIG_DIR"

# Create minimal config without tone mapping or video filters
cat > "$VLC_RC" << 'EOF'
# VLC preferences - Tone mapping disabled

[qt]
qt-privacy-ask=0
qt-continue=0

[core]
# No video filters enabled (tone mapping off)
video-filter=
vout-filter=

# Volume at normal level
audio-volume=256

# No tone mapping
tone-mapping-mode=0
EOF

chown ga:ga "$VLC_RC"
echo "✅ VLC config reset (tone mapping disabled)"

# Launch VLC with the HDR video
echo "Launching VLC with HDR test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop \"$HDR_VIDEO\" > /tmp/vlc_hdr_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_hdr_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_hdr_task.log
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

echo "=== Enable HDR Tone Mapping Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  The HDR video currently looks washed out because your display is SDR."
echo "  Enable tone mapping to fix this:"
echo ""
echo "  1. Open: Tools → Preferences (Ctrl+P)"
echo "  2. Click 'All' (bottom-left) to show advanced settings"
echo "  3. Navigate to: Video → Filters"
echo "  4. Enable the 'Tone mapping' checkbox"
echo "     - OR enable 'Image adjust' filter (legacy approach)"
echo "  5. Optional: Configure tone mapping method under Video → Filters → Tone mapping"
echo "  6. Click 'Save' button to persist settings"
echo "  7. Restart playback or VLC to apply (Ctrl+R to reload)"
echo ""
echo "  Expected: Video colors will look natural instead of washed out"