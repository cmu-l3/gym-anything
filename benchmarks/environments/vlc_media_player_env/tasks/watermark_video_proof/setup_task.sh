#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Watermark Video Proof Task ==="

kill_vlc ga
sleep 1

# Ensure output directory exists
mkdir -p /home/ga/Videos
chown -R ga:ga /home/ga/Videos

# Create input video file for watermarking task
# Use a short 10-second video with some visual content for testing
INPUT_VIDEO="/home/ga/Videos/client_preview_raw.mp4"

if [ ! -f "$INPUT_VIDEO" ]; then
    echo "Creating test input video..."
    
    # Generate a 10-second test video with color bars and timestamp
    # This simulates a client video preview
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=10:size=1280x720:rate=30 \
        -f lavfi -i sine=frequency=1000:duration=10 \
        -vf \"drawtext=text='Sample Client Video':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5\" \
        -c:v libx264 -preset ultrafast -c:a aac -shortest \
        '$INPUT_VIDEO' -y -loglevel error" 2>/dev/null || {
        
        # Fallback: use existing sample video if ffmpeg generation fails
        echo "⚠️ Could not generate test video, using existing sample"
        if [ -f "/home/ga/Videos/sample_video.mp4" ]; then
            cp /home/ga/Videos/sample_video.mp4 "$INPUT_VIDEO"
        else
            echo "ERROR: No sample video available"
            exit 1
        fi
    }
    
    chown ga:ga "$INPUT_VIDEO"
    echo "✅ Input video created: $INPUT_VIDEO"
fi

# Verify input video exists and is valid
if [ ! -f "$INPUT_VIDEO" ] || [ ! -s "$INPUT_VIDEO" ]; then
    echo "ERROR: Input video not found or empty: $INPUT_VIDEO"
    exit 1
fi

echo "Input video info:"
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO" 2>/dev/null || echo "Duration: unknown"

# Launch VLC (without opening convert dialog yet - agent needs to do this)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_watermark_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_watermark_task.log 2>/dev/null || true
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

# Give the window time to fully render
sleep 2

echo "=== Watermark Video Proof Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Open Media → Convert / Save (Ctrl+R)"
echo "  2. Add file: $INPUT_VIDEO"
echo "  3. Click 'Convert / Save' button"
echo "  4. Edit/Select profile to enable video filters:"
echo "     - Click tool icon next to profile dropdown"
echo "     - Go to Video codec tab"
echo "     - Enable 'Overlays/Subtitles' or similar"
echo "     - OR use Filters tab to enable 'Marquee' or 'Text renderer'"
echo "  5. Configure text overlay:"
echo "     - Text: 'PREVIEW ONLY - DO NOT DISTRIBUTE' (or similar)"
echo "     - Position: bottom or center"
echo "     - Opacity: 50-70% (semi-transparent)"
echo "  6. Set destination: /home/ga/Videos/client_preview_watermarked.mp4"
echo "  7. Start conversion"
echo "  8. Wait for conversion to complete"
echo ""
echo "Alternative approach: Use marquee filter with custom text settings"
echo ""