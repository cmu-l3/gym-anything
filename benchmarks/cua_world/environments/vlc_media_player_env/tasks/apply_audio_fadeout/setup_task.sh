#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Apply Audio Fadeout Task ==="

kill_vlc ga
sleep 1

# Create source video if it doesn't exist
SOURCE_VIDEO="/home/ga/Videos/bedtime_story.mp4"

if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "Creating source video: bedtime_story.mp4"
    
    # Generate a 60-second video with test pattern and audio
    # Using testsrc for video and sine wave for audio
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=60:size=640x480:rate=30 \
        -f lavfi -i sine=frequency=440:duration=60 \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k \
        -shortest \
        '$SOURCE_VIDEO' -y > /tmp/ffmpeg_generate.log 2>&1"
    
    if [ ! -f "$SOURCE_VIDEO" ]; then
        echo "ERROR: Failed to create source video"
        cat /tmp/ffmpeg_generate.log
        exit 1
    fi
    
    echo "✅ Source video created ($(du -h "$SOURCE_VIDEO" | cut -f1))"
else
    echo "✅ Source video already exists"
fi

# Verify source video
if ! su - ga -c "ffprobe -v error '$SOURCE_VIDEO' > /dev/null 2>&1"; then
    echo "ERROR: Source video is invalid"
    exit 1
fi

# Ensure output directory exists and is writable
chown -R ga:ga /home/ga/Videos/ 2>/dev/null || true

# Remove any existing output file to ensure clean state
OUTPUT_VIDEO="/home/ga/Videos/bedtime_story_fadeout.mp4"
if [ -f "$OUTPUT_VIDEO" ]; then
    rm -f "$OUTPUT_VIDEO"
    echo "Removed existing output file"
fi

# Launch VLC (optional - agent may use terminal/ffmpeg directly)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_fadeout_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "WARNING: VLC failed to start, but agent can use command-line tools"
else
    if wait_for_window "VLC media player" 20; then
        # Click on center of the screen to select current desktop
        echo "Selecting desktop..."
        su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
        sleep 1

        # Focus window
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid"
        fi
    fi
fi

echo "=== Apply Audio Fadeout Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  Source: /home/ga/Videos/bedtime_story.mp4 (60 seconds)"
echo "  Output: /home/ga/Videos/bedtime_story_fadeout.mp4"
echo ""
echo "  Required: Apply audio fade-out"
echo "    - Start fade at: 45 seconds"
echo "    - Fade duration: 15 seconds"
echo "    - Result: Audio fades to silence by end"
echo ""
echo "  Recommended approach (use terminal):"
echo "    ffmpeg -i /home/ga/Videos/bedtime_story.mp4 \\"
echo "           -af \"afade=t=out:st=45:d=15\" \\"
echo "           -c:v copy \\"
echo "           /home/ga/Videos/bedtime_story_fadeout.mp4"
echo ""
echo "  Alternative: Use VLC Media → Convert/Save with audio filter"
echo ""