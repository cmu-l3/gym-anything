#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Concatenate Split Recordings Task ==="

kill_vlc ga
sleep 1

# Create directory for split recordings
SPLIT_DIR="/home/ga/Videos/split_recording"
mkdir -p "$SPLIT_DIR"
chown ga:ga "$SPLIT_DIR"

# Ensure output directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate 3 test video clips using ffmpeg
# Each clip is ~20 seconds, 1280x720, h264 codec
# Different colors to distinguish parts

echo "Generating test video clips..."

# Part 1: Red color with timestamp
su - ga -c "ffmpeg -f lavfi -i color=c=red:s=1280x720:d=20 -f lavfi -i anoisesrc=d=20:c=pink:r=44100:a=0.5 -vf \"drawtext=text='Part 1 - %{pts\:hms}':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2\" -c:v libx264 -preset fast -pix_fmt yuv420p -c:a aac -shortest '$SPLIT_DIR/recording_part1.mp4' -y > /tmp/ffmpeg_part1.log 2>&1" || {
    echo "ERROR: Failed to generate part1"
    cat /tmp/ffmpeg_part1.log
    exit 1
}

# Part 2: Green color with timestamp
su - ga -c "ffmpeg -f lavfi -i color=c=green:s=1280x720:d=20 -f lavfi -i anoisesrc=d=20:c=pink:r=44100:a=0.5 -vf \"drawtext=text='Part 2 - %{pts\:hms}':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2\" -c:v libx264 -preset fast -pix_fmt yuv420p -c:a aac -shortest '$SPLIT_DIR/recording_part2.mp4' -y > /tmp/ffmpeg_part2.log 2>&1" || {
    echo "ERROR: Failed to generate part2"
    cat /tmp/ffmpeg_part2.log
    exit 1
}

# Part 3: Blue color with timestamp
su - ga -c "ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=20 -f lavfi -i anoisesrc=d=20:c=pink:r=44100:a=0.5 -vf \"drawtext=text='Part 3 - %{pts\:hms}':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2\" -c:v libx264 -preset fast -pix_fmt yuv420p -c:a aac -shortest '$SPLIT_DIR/recording_part3.mp4' -y > /tmp/ffmpeg_part3.log 2>&1" || {
    echo "ERROR: Failed to generate part3"
    cat /tmp/ffmpeg_part3.log
    exit 1
}

echo "✅ Generated 3 video clips:"
ls -lh "$SPLIT_DIR"

# Verify clips were created
for i in 1 2 3; do
    PART_FILE="$SPLIT_DIR/recording_part${i}.mp4"
    if [ ! -f "$PART_FILE" ]; then
        echo "ERROR: Part $i was not created: $PART_FILE"
        exit 1
    fi
    SIZE=$(stat -f%z "$PART_FILE" 2>/dev/null || stat -c%s "$PART_FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -lt 100000 ]; then
        echo "ERROR: Part $i is too small: $SIZE bytes"
        exit 1
    fi
    echo "✅ Part $i: $SIZE bytes"
done

# Store expected durations for verification
echo "20" > /tmp/vlc_concat_part1_duration.txt
echo "20" > /tmp/vlc_concat_part2_duration.txt
echo "20" > /tmp/vlc_concat_part3_duration.txt
echo "60" > /tmp/vlc_concat_expected_total.txt

# Launch VLC in idle state (no file loaded)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_concat_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_concat_task.log
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

echo "=== Concatenate Split Recordings Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Media → Convert/Save (or press Ctrl+R)"
echo "  2. Click 'Add' and navigate to: $SPLIT_DIR"
echo "  3. Add files IN ORDER:"
echo "     - recording_part1.mp4"
echo "     - recording_part2.mp4"
echo "     - recording_part3.mp4"
echo "  4. Click 'Convert / Save' button"
echo "  5. Select profile (e.g., 'Video - H.264 + MP3 (MP4)')"
echo "  6. Set destination: /home/ga/Videos/complete_recording.mp4"
echo "  7. Click 'Start' to begin concatenation"
echo ""
echo "Expected output: ~60 second video at /home/ga/Videos/complete_recording.mp4"