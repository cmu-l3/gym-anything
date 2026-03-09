#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Enhance Telescope Recording Task ==="

kill_vlc ga
sleep 1

# Ensure astronomy directories exist
mkdir -p /home/ga/Videos/astronomy
mkdir -p /home/ga/Pictures/astronomy
chown -R ga:ga /home/ga/Videos/astronomy
chown -R ga:ga /home/ga/Pictures/astronomy

# Reset VLC config to ensure no effects are active
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing video adjustment settings
    sed -i '/^video-filter=/d' "$VLC_RC"
    sed -i '/^adjust-enabled=/d' "$VLC_RC"
    sed -i '/^adjust-gamma=/d' "$VLC_RC"
    sed -i '/^adjust-contrast=/d' "$VLC_RC"
    sed -i '/^adjust-brightness=/d' "$VLC_RC"
    sed -i '/^adjust-saturation=/d' "$VLC_RC"
    sed -i '/^adjust-hue=/d' "$VLC_RC"
    echo "Video adjustment filters reset"
fi

# Generate dark telescope video simulating Andromeda Galaxy observation
TELESCOPE_VIDEO="/home/ga/Videos/astronomy/telescope_andromeda_raw.mp4"

if [ ! -f "$TELESCOPE_VIDEO" ]; then
    echo "Generating dark telescope recording with faint galaxy..."
    
    # Create a very dark video with subtle central brightening (simulating galaxy core)
    # Strategy: Black base + very faint radial gradient for galaxy + noise for stars
    ffmpeg -f lavfi -i color=c=0x050505:s=1280x720:d=45:r=30 \
        -f lavfi -i nullsrc=s=1280x720:d=45:r=30 \
        -filter_complex "\
            [1]geq=\
            lum='clip(20 + 50*exp(-((X-640)*(X-640)+(Y-360)*(Y-360))/40000), 0, 255)':\
            cb=128:cr=128[galaxy];\
            [galaxy]noise=alls=8:allf=t[galaxy_noise];\
            [0][galaxy_noise]blend=all_mode=screen:all_opacity=0.15[v];\
            [v]format=yuv420p[out]" \
        -map "[out]" \
        -c:v libx264 -preset fast -crf 28 \
        -y "$TELESCOPE_VIDEO"
    
    chown ga:ga "$TELESCOPE_VIDEO"
    echo "✅ Telescope recording generated: $TELESCOPE_VIDEO"
else
    echo "Telescope recording already exists"
fi

# Verify video was created
if [ ! -f "$TELESCOPE_VIDEO" ]; then
    echo "ERROR: Failed to create telescope recording"
    exit 1
fi

# Ensure snapshot directory exists and is empty
rm -f /home/ga/Pictures/astronomy/*.png 2>/dev/null || true

# Configure VLC snapshot settings
if [ -f "$VLC_RC" ]; then
    # Ensure snapshot settings are configured
    if ! grep -q "^snapshot-path=" "$VLC_RC"; then
        echo "snapshot-path=/home/ga/Pictures/astronomy" >> "$VLC_RC"
    else
        sed -i 's|^snapshot-path=.*|snapshot-path=/home/ga/Pictures/astronomy|' "$VLC_RC"
    fi
    
    if ! grep -q "^snapshot-format=" "$VLC_RC"; then
        echo "snapshot-format=png" >> "$VLC_RC"
    else
        sed -i 's|^snapshot-format=.*|snapshot-format=png|' "$VLC_RC"
    fi
    
    if ! grep -q "^snapshot-prefix=" "$VLC_RC"; then
        echo "snapshot-prefix=andromeda_enhanced" >> "$VLC_RC"
    else
        sed -i 's|^snapshot-prefix=.*|snapshot-prefix=andromeda_enhanced|' "$VLC_RC"
    fi
    
    echo "Snapshot settings configured"
fi

# Launch VLC with telescope recording and RC interface
echo "Launching VLC with telescope recording..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$TELESCOPE_VIDEO' > /tmp/vlc_telescope_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_telescope_task.log
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

# Let video play briefly to initialize
sleep 2

# Pause the video
echo "Pausing video for agent control..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

echo "=== Enhance Telescope Recording Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video is paused and playing in VLC"
echo "  2. The recording is VERY dark - you can barely see a faint glow in the center"
echo "  3. Open Effects and Filters: Tools → Effects and Filters (Ctrl+E)"
echo "  4. Go to Video Effects → Essential tab"
echo "  5. Enable 'Image adjust' checkbox"
echo "  6. Adjust sliders:"
echo "     - Gamma: ~2.0 (≥1.5 required)"
echo "     - Contrast: ~1.5 (≥1.3 required)"
echo "     - Brightness: ~0.15 (≥0.1 required)"
echo "  7. Close effects dialog (settings save automatically)"
echo "  8. Seek to ~15-20 seconds (press Space to play, or use Shift+Right)"
echo "  9. Take snapshot: Video → Take Snapshot (or Shift+S)"
echo "  10. Snapshot should be saved as: andromeda_enhanced*.png"
echo ""
echo "Expected output: /home/ga/Pictures/astronomy/andromeda_enhanced*.png"