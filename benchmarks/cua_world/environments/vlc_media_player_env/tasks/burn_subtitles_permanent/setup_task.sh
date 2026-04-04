#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Burn Subtitles Permanently Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure output directory exists
mkdir -p /home/ga/Videos/converted
chown ga:ga /home/ga/Videos/converted

# Remove any previous output
rm -f /home/ga/Videos/converted/film_with_burned_subs.mp4

# Generate sample video (30 seconds, 1280x720, H.264)
echo "Generating sample video..."
VIDEO_FILE="/home/ga/Videos/foreign_film_sample.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 \
        -f lavfi -i sine=frequency=440:duration=30 \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k \
        -y "$VIDEO_FILE" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to generate sample video"
        exit 1
    fi
    
    chown ga:ga "$VIDEO_FILE"
    echo "✅ Sample video generated: $VIDEO_FILE"
else
    echo "✅ Sample video already exists: $VIDEO_FILE"
fi

# Create subtitle file (SRT format)
echo "Creating subtitle file..."
SUBTITLE_FILE="/home/ga/Videos/foreign_film_sample.srt"

cat > "$SUBTITLE_FILE" << 'EOF'
1
00:00:01,000 --> 00:00:04,000
This is the first subtitle line.

2
00:00:05,500 --> 00:00:08,500
And here's a second line of dialogue.

3
00:00:10,000 --> 00:00:14,000
Testing subtitle burning in VLC.

4
00:00:15,500 --> 00:00:19,000
Final subtitle for verification.

5
00:00:20,000 --> 00:00:24,000
This ensures subtitles are present throughout.
EOF

chown ga:ga "$SUBTITLE_FILE"
echo "✅ Subtitle file created: $SUBTITLE_FILE"

# Verify files exist and have content
if [ ! -f "$VIDEO_FILE" ] || [ ! -s "$VIDEO_FILE" ]; then
    echo "ERROR: Video file not created or is empty"
    exit 1
fi

if [ ! -f "$SUBTITLE_FILE" ] || [ ! -s "$SUBTITLE_FILE" ]; then
    echo "ERROR: Subtitle file not created or is empty"
    exit 1
fi

# Launch VLC (GUI mode for agent to use conversion dialog)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_burn_subs_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_burn_subs_task.log
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

echo "=== Burn Subtitles Permanently Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video file: /home/ga/Videos/foreign_film_sample.mp4"
echo "  2. Subtitle file: /home/ga/Videos/foreign_film_sample.srt"
echo "  3. Open Media → Convert/Save (Ctrl+R)"
echo "  4. Add video file, enable 'Show more options', load subtitle file"
echo "  5. Click Convert/Save, choose H.264 MP4 profile"
echo "  6. CRITICAL: Enable 'Overlay subtitles on the video' option"
echo "  7. Set destination: /home/ga/Videos/converted/film_with_burned_subs.mp4"
echo "  8. Start conversion and wait for completion"
echo ""
echo "🎯 Goal: Create video with subtitles burned into frames (no separate subtitle track)"