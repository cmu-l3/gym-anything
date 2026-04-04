#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Enable Resume Playback Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure test video exists (3-minute video with timestamp overlay)
TEST_VIDEO="/home/ga/Videos/lecture_recording.mp4"
if [ ! -f "$TEST_VIDEO" ]; then
    echo "Creating test video with timestamp overlay..."
    mkdir -p /home/ga/Videos
    
    # Generate a 3-minute test video with visible timestamp
    ffmpeg -f lavfi -i testsrc=duration=180:size=1280x720:rate=30 \
           -f lavfi -i sine=frequency=440:duration=180 \
           -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
                text='Lecture Recording\nTime\: %{pts\:hms}':fontsize=48:fontcolor=white:\
                x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.7:boxborderw=10" \
           -c:v libx264 -preset veryfast -c:a aac \
           "$TEST_VIDEO" 2>/tmp/ffmpeg_lecture_video.log || {
        echo "ERROR: Failed to create test video"
        exit 1
    }
    
    chown ga:ga "$TEST_VIDEO"
    echo "✅ Created test video: $TEST_VIDEO (180 seconds)"
else
    echo "✅ Test video already exists: $TEST_VIDEO"
fi

# Reset VLC configuration to disable resume playback
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc
chown -R ga:ga /home/ga/.config/vlc

if [ -f "$VLC_CONFIG" ]; then
    # Remove or set qt-continue to 0 (disabled)
    sed -i '/^qt-continue=/d' "$VLC_CONFIG"
    echo "# Resume playback disabled by setup" >> "$VLC_CONFIG"
    echo "qt-continue=0" >> "$VLC_CONFIG"
    echo "✅ VLC config reset: resume playback DISABLED"
else
    # Create minimal config with resume disabled
    cat > "$VLC_CONFIG" <<EOF
# VLC preferences - reset for enable_resume_playback task
[qt]
qt-continue=0
EOF
    chown ga:ga "$VLC_CONFIG"
    echo "✅ Created new VLC config with resume DISABLED"
fi

# Clear VLC media library and recent items (fresh state)
rm -f /home/ga/.local/share/vlc/ml.xspf 2>/dev/null || true
rm -rf /home/ga/.cache/vlc/* 2>/dev/null || true
echo "✅ Cleared VLC media library and cache"

# Clean up any previous verification files
rm -f /home/ga/resume_verification.txt 2>/dev/null || true
rm -f /tmp/vlc_resume_*.txt 2>/dev/null || true
rm -f /tmp/vlc_resume_*.json 2>/dev/null || true

# Launch VLC (empty, no video loaded yet)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_resume_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_resume_task.log 2>/dev/null || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 400 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "✅ VLC window focused"
fi

# Give VLC time to fully initialize
sleep 2

echo ""
echo "=== Enable Resume Playback Task Setup Complete ==="
echo ""
echo "📋 Current State:"
echo "  - VLC is running (empty window)"
echo "  - Resume playback is DISABLED (qt-continue=0)"
echo "  - Test video available: $TEST_VIDEO"
echo ""
echo "📝 Instructions for Agent:"
echo "  1. Open VLC Preferences:"
echo "     Method A: Menu → Tools → Preferences (Ctrl+P)"
echo "     Method B: Settings → Preferences"
echo ""
echo "  2. Enable resume playback:"
echo "     - In Simple preferences, look for:"
echo "       • 'Continue playback?' option"
echo "       • 'Ask to resume playback' checkbox"
echo "     - Enable it (check the box or set to 'Ask' or 'Always')"
echo ""
echo "  3. Save preferences:"
echo "     - Click 'Save' button at bottom of preferences window"
echo ""
echo "  4. (Optional) Test the feature:"
echo "     - Open $TEST_VIDEO"
echo "     - Play to ~90 seconds"
echo "     - Close VLC (Ctrl+Q)"
echo "     - Reopen the video"
echo "     - Verify resume dialog appears or auto-resumes"
echo ""
echo "  5. (Optional) Document test:"
echo "     - Create /home/ga/resume_verification.txt with:"
echo "       Stop position: HH:MM:SS"
echo "       Resume position: HH:MM:SS"
echo "       Verification status: SUCCESS"
echo ""