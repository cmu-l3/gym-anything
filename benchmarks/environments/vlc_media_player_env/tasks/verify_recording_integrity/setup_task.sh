#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Recording Integrity Task ==="

kill_vlc ga
sleep 1

# Ensure output directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate synthetic gameplay recording with planted audio issue
RECORDING_FILE="/home/ga/Videos/gameplay_recording.mkv"

echo "Generating synthetic recording with audio issue..."

# Create 60-second test video with two audio tracks
# Track 0: Game audio (normal volume)
# Track 1: Microphone (very low volume - 5% = -26dB)
ffmpeg -y \
  -f lavfi -i testsrc=duration=60:size=1920x1080:rate=30 \
  -f lavfi -i "sine=frequency=440:duration=60" \
  -f lavfi -i "sine=frequency=220:duration=60" \
  -map 0:v -map 1:a -map 2:a \
  -c:v libx264 -preset fast -crf 22 -pix_fmt yuv420p \
  -c:a:0 aac -b:a:0 192k \
  -c:a:1 aac -b:a:1 192k -filter:a:1 "volume=0.05" \
  -metadata:s:a:0 title="Game Audio" \
  -metadata:s:a:1 title="Microphone" \
  "$RECORDING_FILE" \
  > /tmp/ffmpeg_recording_gen.log 2>&1

if [ ! -f "$RECORDING_FILE" ]; then
    echo "ERROR: Failed to generate recording file"
    cat /tmp/ffmpeg_recording_gen.log
    exit 1
fi

chown ga:ga "$RECORDING_FILE"

echo "✅ Recording file generated: $RECORDING_FILE"
ls -lh "$RECORDING_FILE"

# Verify file was created correctly
echo "Verifying recording file properties..."
ffprobe -v error -show_streams -of json "$RECORDING_FILE" > /tmp/recording_info.json 2>&1

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_verify_recording_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Verify Recording Integrity Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open the recording file: /home/ga/Videos/gameplay_recording.mkv"
echo "     (Use Media → Open File or Ctrl+O)"
echo "  2. Check Media Information (Tools → Codec Information or Ctrl+J)"
echo "  3. Verify video specs:"
echo "     - Resolution: 1920x1080"
echo "     - Framerate: 30fps"
echo "     - Codec: H.264"
echo "  4. Check audio tracks (2 tracks expected)"
echo "  5. Play and verify audio from both tracks"
echo "     (Use Audio → Audio Track to switch between tracks)"
echo "  6. ISSUE: Track 2 (Microphone) has very low volume"
echo "  7. Create verification report at:"
echo "     /home/ga/Videos/recording_verification_report.txt"
echo "  8. Report should include:"
echo "     - Video specifications check"
echo "     - Audio track count"
echo "     - Issue identification (low mic volume)"
echo "     - Recommendation (re-record with mic fix)"