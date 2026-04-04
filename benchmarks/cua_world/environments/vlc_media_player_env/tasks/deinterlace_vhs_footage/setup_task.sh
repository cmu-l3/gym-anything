#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Deinterlace VHS Footage Task ==="

kill_vlc ga
sleep 1

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Create interlaced video file (simulating digitized VHS with interlacing artifacts)
echo "Creating interlaced video file (simulating VHS footage)..."
INTERLACED_VIDEO="/home/ga/Videos/family_vhs_1992.mp4"

if [ ! -f "$INTERLACED_VIDEO" ]; then
    # Generate test video with motion and apply interlacing
    # This simulates a digitized VHS tape with interlacing artifacts
    ffmpeg -f lavfi -i "testsrc=duration=30:size=720x480:rate=30000/1001" \
           -vf "interlace" \
           -c:v libx264 -preset fast -flags +ilme+ildct \
           -pix_fmt yuv420p \
           -y "$INTERLACED_VIDEO" > /tmp/ffmpeg_interlace.log 2>&1 || {
        echo "ERROR: Failed to create interlaced video"
        cat /tmp/ffmpeg_interlace.log
        exit 1
    }
    
    chown ga:ga "$INTERLACED_VIDEO"
    echo "✅ Interlaced video created: $INTERLACED_VIDEO"
else
    echo "✅ Interlaced video already exists"
fi

# Reset VLC config to ensure deinterlacing is initially disabled
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

mkdir -p "$VLC_CONFIG_DIR"
chown ga:ga "$VLC_CONFIG_DIR"

if [ -f "$VLC_RC" ]; then
    # Remove any existing deinterlace settings to start fresh
    sed -i '/^deinterlace=/d' "$VLC_RC"
    sed -i '/^deinterlace-mode=/d' "$VLC_RC"
    sed -i '/^sout-deinterlace-mode=/d' "$VLC_RC"
    sed -i '/^video-filter=/d' "$VLC_RC"
    echo "VLC config reset (deinterlacing disabled)"
else
    # Create minimal config with deinterlacing disabled
    cat > "$VLC_RC" <<EOF
# VLC preferences
[core]
EOF
    chown ga:ga "$VLC_RC"
    echo "VLC config initialized"
fi

# Launch VLC with the interlaced video
echo "Launching VLC with interlaced video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$INTERLACED_VIDEO' > /tmp/vlc_deinterlace_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_deinterlace_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_deinterlace_task.log
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

# Wait for video to start playing
sleep 2

echo "=== Deinterlace VHS Footage Task Setup Complete ==="
echo ""
echo "📺 SCENARIO: You have digitized VHS home videos from 1992."
echo "   The footage shows visible horizontal 'comb' lines during motion."
echo "   This is due to interlacing artifacts from the analog source."
echo ""
echo "📝 YOUR TASK: Enable deinterlacing to fix the video quality."
echo ""
echo "💡 Instructions:"
echo "  1. Open Tools → Preferences (or press Ctrl+P)"
echo "  2. Click 'Show settings: All' at bottom left (if in Simple mode)"
echo "  3. Navigate to: Video → Filters"
echo "  4. Check the 'Deinterlacing video filter' checkbox"
echo "  5. Then go to: Video → Filters → Deinterlace"
echo "  6. Set 'Deinterlacing mode' to a valid algorithm (e.g., 'Yadif', 'Linear', 'Bob')"
echo "  7. Click 'Save' to persist settings"
echo "  8. Close preferences window"
echo ""
echo "⚡ Alternative (simpler) method:"
echo "  1. Go to Video menu → Deinterlace"
echo "  2. Select 'On' or choose a specific mode (Blend, Bob, Linear, Yadif, etc.)"
echo "  3. This should persist in VLC settings"
echo ""
echo "✅ Success criteria: VLC config must show deinterlacing enabled"