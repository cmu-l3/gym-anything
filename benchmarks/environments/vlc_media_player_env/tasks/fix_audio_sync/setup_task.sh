#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Audio Sync Task ==="

kill_vlc ga
sleep 1

# Ensure video directory exists
VIDEO_DIR="/home/ga/Videos"
ASYNC_VIDEO="$VIDEO_DIR/lecture_async.mp4"

mkdir -p "$VIDEO_DIR"

# Create a test video with audio sync issues (audio 350ms early)
# This simulates a poorly encoded lecture recording
echo "Creating test video with audio sync issues..."

# Strategy: Create a simple video with visual and audio cues that make sync obvious
# Use color flashes synchronized with beep sounds, then offset the audio

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found, attempting to install..."
    apt-get update && apt-get install -y ffmpeg
fi

# Generate base video: 30 seconds with periodic visual flashes and audio beeps
# The flashes and beeps should be synchronized, making desync obvious
cat > /tmp/generate_sync_test.sh << 'FFMPEG_SCRIPT'
#!/bin/bash
set -e

# Create a video with 6 flash/beep events (every 5 seconds)
# Each flash is a white screen for 0.1s, each beep is 440Hz for 0.1s

# First create video with visual flashes
ffmpeg -f lavfi -i color=c=black:s=1280x720:d=30:r=30 \
  -vf "drawtext=text='AUDIO SYNC TEST - Listen for beeps':fontsize=32:fontcolor=white:x=(w-text_w)/2:y=50,\
       drawtext=text='Audio should match flash':fontsize=24:fontcolor=yellow:x=(w-text_w)/2:y=100,\
       geq=lum='if(between(mod(N\,150),0,3),255,16)':cb=128:cr=128" \
  -pix_fmt yuv420p -y /tmp/video_base.mp4 2>/dev/null

# Create audio track with beeps every 5 seconds (at frames 0, 150, 300, 450, 600, 750)
# Generate 6 beeps using sine wave
ffmpeg -f lavfi -i "sine=frequency=440:duration=0.1,apad=pad_dur=4.9" -i \
  "sine=frequency=440:duration=0.1,apad=pad_dur=4.9" -i \
  "sine=frequency=440:duration=0.1,apad=pad_dur=4.9" -i \
  "sine=frequency=440:duration=0.1,apad=pad_dur=4.9" -i \
  "sine=frequency=440:duration=0.1,apad=pad_dur=4.9" -i \
  "sine=frequency=440:duration=0.1,apad=pad_dur=4.9" \
  -filter_complex "[0][1][2][3][4][5]concat=n=6:v=0:a=1[aout]" \
  -map "[aout]" -y /tmp/audio_base.aac 2>/dev/null

# Combine video and audio
ffmpeg -i /tmp/video_base.mp4 -i /tmp/audio_base.aac \
  -c:v copy -c:a aac -shortest -y /tmp/video_synced.mp4 2>/dev/null

# Now create the desync version by shifting audio 350ms EARLIER (negative offset)
# This makes audio arrive before video, which is the problem to fix
ffmpeg -i /tmp/video_synced.mp4 -itsoffset 0.35 -i /tmp/video_synced.mp4 \
  -map 1:v:0 -map 0:a:0 -c:v copy -c:a copy \
  -y /tmp/video_async.mp4 2>/dev/null || {
    echo "Warning: Advanced sync offset failed, using simpler method"
    # Fallback: just use the synced video and document the issue
    cp /tmp/video_synced.mp4 /tmp/video_async.mp4
}

echo "Sync test video created"
FFMPEG_SCRIPT

chmod +x /tmp/generate_sync_test.sh

# Try to generate the video, with fallback to existing sample
if bash /tmp/generate_sync_test.sh 2>/tmp/video_gen.log; then
    cp /tmp/video_async.mp4 "$ASYNC_VIDEO"
    echo "✅ Created async test video"
else
    echo "⚠️ Video generation failed, using sample video as fallback"
    cat /tmp/video_gen.log || true
    
    # Fallback: use existing sample video and document sync issue
    if [ -f "$VIDEO_DIR/sample_video.mp4" ]; then
        cp "$VIDEO_DIR/sample_video.mp4" "$ASYNC_VIDEO"
    else
        # Last resort: download a test video
        echo "Downloading test video..."
        wget -q -O "$ASYNC_VIDEO" "https://download.blender.org/demo/movies/BBB/bbb_sunflower_1080p_30fps_normal.mp4.zip" || {
            echo "ERROR: Could not create or download test video"
            exit 1
        }
    fi
fi

# Ensure video exists and has reasonable size
if [ ! -f "$ASYNC_VIDEO" ] || [ $(stat -f%z "$ASYNC_VIDEO" 2>/dev/null || stat -c%s "$ASYNC_VIDEO") -lt 10000 ]; then
    echo "ERROR: Video file invalid or too small"
    exit 1
fi

# Set ownership
chown ga:ga "$ASYNC_VIDEO" 2>/dev/null || true

echo "Video ready at: $ASYNC_VIDEO"

# Clear any existing VLC audio delay settings from config
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove existing audio delay/desync settings
    sed -i '/^audio-desync=/d' "$VLC_RC" 2>/dev/null || true
    sed -i '/^desync=/d' "$VLC_RC" 2>/dev/null || true
    sed -i '/^audio-time-stretch=/d' "$VLC_RC" 2>/dev/null || true
    echo "Cleared existing audio delay settings"
fi

# Launch VLC with RC interface enabled
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$ASYNC_VIDEO' > /tmp/vlc_sync_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_sync_task.log || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Give time for video to start playing
sleep 2

echo "=== Fix Audio Sync Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. The video at $ASYNC_VIDEO has audio sync issues"
echo "  2. Audio arrives approximately 350ms BEFORE video (too early)"
echo "  3. You need to DELAY the audio to match video"
echo "  4. Use Tools → Track Synchronization → Audio desync"
echo "  5. Set a POSITIVE delay value (~300-400ms)"
echo "  6. Alternative: Press 'j' key multiple times to delay audio"
echo "  7. Each 'j' press adds 50ms delay"
echo "  8. Test by watching - beeps should align with flashes"
echo ""
echo "Expected correction: +300 to +400 milliseconds"