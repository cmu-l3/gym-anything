#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Reaction GIF Task ==="

kill_vlc ga
sleep 1

# Ensure export directory exists
mkdir -p /home/ga/Videos/exports
chown ga:ga /home/ga/Videos/exports

# Clean any previous output
rm -f /home/ga/Videos/exports/reaction.gif
rm -f /home/ga/Videos/exports/*.gif

# Create source video with distinct visual content at the target segment
# This ensures we can verify the correct segment was extracted
SOURCE_VIDEO="/home/ga/Videos/sample_content.mp4"

if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "Creating source video with distinct visual markers..."
    
    # Create a 20-second video with changing colors/text at different timestamps
    # The segment from 12.5-16.0s will have a distinct visual pattern
    su - ga -c "ffmpeg -y -f lavfi -i color=c=blue:s=1280x720:d=10 \
        -f lavfi -i color=c=red:s=1280x720:d=4 \
        -f lavfi -i color=c=green:s=1280x720:d=6 \
        -filter_complex '[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]; \
            [outv]drawtext=text=\"Timestamp\\: %{pts\\:hms}\": \
            x=(w-text_w)/2:y=(h-text_h)/2:fontsize=48:fontcolor=white[v]' \
        -map '[v]' -r 30 -pix_fmt yuv420p '$SOURCE_VIDEO' > /tmp/create_source_video.log 2>&1" || {
        echo "Failed to create source video with ffmpeg, using existing sample"
        # Fallback to existing sample if ffmpeg creation fails
        if [ -f "/home/ga/Videos/sample_video.mp4" ]; then
            cp /home/ga/Videos/sample_video.mp4 "$SOURCE_VIDEO"
        else
            echo "ERROR: No source video available"
            exit 1
        fi
    }
    
    chown ga:ga "$SOURCE_VIDEO"
fi

# Verify source video exists
if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "ERROR: Source video not found: $SOURCE_VIDEO"
    exit 1
fi

echo "Source video ready: $SOURCE_VIDEO"
ls -lh "$SOURCE_VIDEO"

# Get video info
ffprobe -v error -select_streams v:0 -show_entries stream=duration,width,height -of default=noprint_wrappers=1 "$SOURCE_VIDEO" || true

# Launch VLC with the source video
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show '$SOURCE_VIDEO' > /tmp/vlc_gif_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_gif_task.log || true
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

# Let video start playing briefly so VLC is fully initialized
sleep 2

# Pause the video
echo "Pausing video for agent to work..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

echo "=== Create Reaction GIF Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Source video: $SOURCE_VIDEO"
echo "  2. Extract segment from 12.5 seconds to 16.0 seconds (3.5s duration)"
echo "  3. Convert to animated GIF format"
echo "  4. Save to: /home/ga/Videos/exports/reaction.gif"
echo ""
echo "  Recommended approach:"
echo "    - Media → Convert/Save (Ctrl+R)"
echo "    - Add source file"
echo "    - Set start time: 12.5s"
echo "    - Set stop time: 16.0s (or duration: 3.5s)"
echo "    - Choose GIF format/profile"
echo "    - Set frame rate: ~12 fps"
echo "    - Set max width: 480px"
echo "    - Start conversion"
echo ""
echo "  Requirements:"
echo "    ✓ Duration: 3.5 seconds (±0.3s)"
echo "    ✓ File size: ≤ 8 MB"
echo "    ✓ Max width: 480px"
echo "    ✓ Animated (multiple frames)"
echo "    ✓ Frame rate: 10-15 fps recommended"