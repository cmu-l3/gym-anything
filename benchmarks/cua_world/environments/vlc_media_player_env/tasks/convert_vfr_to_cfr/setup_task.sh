#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Convert VFR to CFR Task ==="

kill_vlc ga
sleep 1

# Ensure output directory exists
mkdir -p /home/ga/Videos
chown -R ga:ga /home/ga/Videos

# Create a realistic VFR video simulating OBS screen recording
echo "Generating VFR test video (simulating OBS recording with mixed frame rates)..."

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found, cannot generate test video"
    exit 1
fi

# Generate two segments with different frame rates to create VFR
# Segment 1: 30fps for 60 seconds (static content simulation)
echo "Creating 30fps segment..."
ffmpeg -f lavfi -i testsrc=duration=60:size=1920x1080:rate=30 \
  -f lavfi -i sine=frequency=440:duration=60 \
  -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ar 44100 \
  /tmp/segment_30fps.mp4 -y 2>/dev/null

# Segment 2: 60fps for 60 seconds (action content simulation)
echo "Creating 60fps segment..."
ffmpeg -f lavfi -i testsrc=duration=60:size=1920x1080:rate=60 \
  -f lavfi -i sine=frequency=880:duration=60 \
  -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ar 44100 \
  /tmp/segment_60fps.mp4 -y 2>/dev/null

# Concatenate with concat demuxer (preserves VFR nature)
echo "Concatenating segments to create VFR video..."
echo "file '/tmp/segment_30fps.mp4'" > /tmp/concat_list.txt
echo "file '/tmp/segment_60fps.mp4'" >> /tmp/concat_list.txt

ffmpeg -f concat -safe 0 -i /tmp/concat_list.txt \
  -c copy \
  /home/ga/Videos/screen_recording_vfr.mkv -y 2>/dev/null

# Verify VFR characteristics
echo "Verifying VFR characteristics..."
VFR_CHECK=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=r_frame_rate,avg_frame_rate \
  -of default=noprint_wrappers=1:nokey=1 \
  /home/ga/Videos/screen_recording_vfr.mkv 2>/dev/null || echo "")

echo "Frame rate info: $VFR_CHECK"

# Clean up temp segments
rm -f /tmp/segment_*.mp4 /tmp/concat_list.txt

# Set proper permissions
chown ga:ga /home/ga/Videos/screen_recording_vfr.mkv
chmod 644 /home/ga/Videos/screen_recording_vfr.mkv

# Verify file was created
if [ ! -f /home/ga/Videos/screen_recording_vfr.mkv ]; then
    echo "ERROR: Failed to create VFR test video"
    exit 1
fi

FILE_SIZE=$(stat -f%z /home/ga/Videos/screen_recording_vfr.mkv 2>/dev/null || stat -c%s /home/ga/Videos/screen_recording_vfr.mkv 2>/dev/null)
echo "✅ VFR test video created: $(echo "scale=1; $FILE_SIZE / 1024 / 1024" | bc 2>/dev/null || echo '?') MB"

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_convert_vfr_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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

sleep 1

echo "=== Convert VFR to CFR Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Convert /home/ga/Videos/screen_recording_vfr.mkv to CFR format"
echo "  2. Use Media → Convert/Save (Ctrl+R)"
echo "  3. Add source file: /home/ga/Videos/screen_recording_vfr.mkv"
echo "  4. Click 'Convert/Save' button (NOT 'Play')"
echo "  5. Select or create profile with settings:"
echo "     - Container: MP4"
echo "     - Video codec: H.264"
echo "     - Frame rate: 30 fps (IMPORTANT: set explicit FPS, not 'keep original')"
echo "     - Audio codec: AAC"
echo "  6. Set destination: /home/ga/Videos/screen_recording_cfr.mp4"
echo "  7. Click 'Start' to begin conversion"
echo "  8. Wait for conversion to complete (~30-60 seconds)"
echo ""
echo "⚠️  Key point: Must set frame rate to 30fps explicitly for CFR output"