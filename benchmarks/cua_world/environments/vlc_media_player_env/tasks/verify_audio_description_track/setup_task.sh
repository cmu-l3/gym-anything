#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Audio Description Track Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create test directory
TEST_DIR="/home/ga/Videos/accessibility_test"
mkdir -p "$TEST_DIR"
chown ga:ga "$TEST_DIR"

cd "$TEST_DIR"

# Check if test video already exists
if [ -f "$TEST_DIR/wildlife_doc.mp4" ]; then
    echo "Test video already exists, checking audio tracks..."
    AUDIO_TRACKS=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$TEST_DIR/wildlife_doc.mp4" 2>/dev/null | wc -l || echo "0")
    
    if [ "$AUDIO_TRACKS" -ge 2 ]; then
        echo "✅ Test video has $AUDIO_TRACKS audio tracks, using existing file"
    else
        echo "⚠️ Existing video has insufficient tracks, regenerating..."
        rm -f "$TEST_DIR/wildlife_doc.mp4"
    fi
fi

# Generate test video if it doesn't exist
if [ ! -f "$TEST_DIR/wildlife_doc.mp4" ]; then
    echo "Generating multi-track test video with ffmpeg..."
    
    # Generate a 30-second test pattern video with nature-themed visuals
    # Using mandelbrot fractal generator to simulate wildlife documentary visuals
    ffmpeg -f lavfi -i "mandelbrot=size=1920x1080:rate=30" -t 30 \
           -f lavfi -i "sine=frequency=220:duration=30" \
           -filter_complex "[0:v]drawtext=text='Wildlife Documentary - Accessibility Test':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=50:box=1:boxcolor=black@0.5:boxborderw=5,drawtext=text='Video with Audio Description':fontsize=32:fontcolor=yellow:x=(w-text_w)/2:y=150[v]" \
           -map "[v]" -map "1:a" \
           -c:v libx264 -preset ultrafast -crf 28 -c:a aac -b:a 128k \
           temp_main_video.mp4 -y 2>/tmp/vlc_ad_setup.log || {
        echo "ERROR: Failed to generate base video"
        cat /tmp/vlc_ad_setup.log
        exit 1
    }
    
    # Generate audio description track (narration simulation)
    # Use different frequency and add volume ducking to simulate voice narration
    ffmpeg -f lavfi -i "sine=frequency=180:duration=30" \
           -af "volume=0.5,atempo=0.95" \
           -c:a aac -b:a 96k \
           ad_narration.aac -y 2>>/tmp/vlc_ad_setup.log || {
        echo "ERROR: Failed to generate AD track"
        exit 1
    }
    
    # Combine video with both audio tracks using proper metadata
    ffmpeg -i temp_main_video.mp4 -i ad_narration.aac \
           -map 0:v -map 0:a -map 1:a \
           -metadata:s:a:0 language=eng -metadata:s:a:0 title="Main Audio" \
           -metadata:s:a:1 language=eng -metadata:s:a:1 title="Audio Description" \
           -c:v copy -c:a aac \
           wildlife_doc.mp4 -y 2>>/tmp/vlc_ad_setup.log || {
        echo "ERROR: Failed to combine audio tracks"
        cat /tmp/vlc_ad_setup.log
        exit 1
    }
    
    # Cleanup temporary files
    rm -f temp_main_video.mp4 ad_narration.aac
    
    echo "✅ Multi-track video generated"
fi

# Verify file was created with correct properties
if [ ! -f "$TEST_DIR/wildlife_doc.mp4" ]; then
    echo "ERROR: Test video file not found after generation"
    exit 1
fi

# Verify audio track count
AUDIO_TRACKS=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$TEST_DIR/wildlife_doc.mp4" 2>/dev/null | wc -l || echo "0")

if [ "$AUDIO_TRACKS" -lt 2 ]; then
    echo "ERROR: Video does not have 2 audio tracks (found: $AUDIO_TRACKS)"
    ffprobe -v error -show_streams "$TEST_DIR/wildlife_doc.mp4" 2>&1 | head -30
    exit 1
fi

echo "✅ Test video verified: $AUDIO_TRACKS audio tracks"

# Set permissions
chown -R ga:ga "$TEST_DIR"
chmod 644 "$TEST_DIR/wildlife_doc.mp4"

# Reset VLC config to ensure default audio track selection
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc

# Remove any existing audio track preferences to ensure fresh state
if [ -f "$VLC_RC" ]; then
    sed -i '/^audio-track=/d' "$VLC_RC"
    sed -i '/^sout-transcode-aenc=/d' "$VLC_RC"
    echo "VLC audio track preference reset"
fi

# Create minimal VLC config
cat > "$VLC_RC" << 'EOF'
[qt]
qt-privacy-ask=0
qt-start-minimized=0

[core]
audio-track=-1
metadata-network-access=0
EOF

chown -R ga:ga /home/ga/.config/vlc

# Launch VLC with RC interface and the test video
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$TEST_DIR/wildlife_doc.mp4' > /tmp/vlc_ad_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_ad_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..15}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    echo "RC interface not ready, waiting... ($i/15)"
    sleep 1
done

# Click on center of screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "VLC window focused (WID: $wid)"
fi

# Ensure video is playing
sleep 2

echo "=== Verify Audio Description Track Task Setup Complete ==="
echo ""
echo "📋 Task Information:"
echo "  📁 Video file: $TEST_DIR/wildlife_doc.mp4"
echo "  🎵 Audio tracks: $AUDIO_TRACKS"
echo "     - Track 1: Main Audio (ambient sounds)"
echo "     - Track 2: Audio Description (narration for blind users)"
echo ""
echo "📝 Instructions for Agent:"
echo "  1. VLC is now playing the wildlife documentary"
echo "  2. Open Audio menu (Audio → Audio Track in menu bar)"
echo "  3. You should see 2 audio tracks listed"
echo "  4. Select 'Track 2' or 'Audio Description' track"
echo "  5. Alternative methods:"
echo "     - Right-click → Audio → Audio Track → Track 2"
echo "     - Press 'B' key to cycle through audio tracks"
echo "  6. Verify both main audio and AD narration are audible"
echo "  7. The AD track should remain selected when complete"
echo ""
echo "✅ Setup complete - agent can now begin task"