#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Select Audio Track Task ==="

kill_vlc ga
sleep 1

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Create test video with multiple audio tracks
echo "Creating multi-audio test video..."
cd /home/ga/Videos

# Generate a 30-second video with 3 distinct audio tracks
# Track 0: Japanese (simulated with 440Hz sine wave - lower frequency)
# Track 1: English Dub (simulated with 523Hz sine wave - higher frequency)
# Track 2: English Audio Description (simulated with 349Hz sine wave - different frequency)

# Create video with color patterns to make it visually interesting
ffmpeg -f lavfi -i "testsrc=duration=30:size=1280x720:rate=24" \
       -f lavfi -i "sine=frequency=440:duration=30" \
       -f lavfi -i "sine=frequency=523:duration=30" \
       -f lavfi -i "sine=frequency=349:duration=30" \
       -map 0:v -map 1:a -map 2:a -map 3:a \
       -metadata:s:a:0 language=jpn -metadata:s:a:0 title="Japanese" \
       -metadata:s:a:1 language=eng -metadata:s:a:1 title="English Dub" \
       -metadata:s:a:2 language=eng -metadata:s:a:2 title="English AD" \
       -c:v libx264 -preset ultrafast -crf 23 \
       -c:a aac -b:a 128k \
       -y test_multi_audio.mkv \
       > /tmp/vlc_audio_track_ffmpeg.log 2>&1

if [ ! -f "test_multi_audio.mkv" ]; then
    echo "ERROR: Failed to create test video"
    cat /tmp/vlc_audio_track_ffmpeg.log
    exit 1
fi

# Verify file was created with multiple audio tracks
TRACK_COUNT=$(ffprobe -v error -select_streams a -show_entries stream=index \
              -of csv=p=0 test_multi_audio.mkv 2>/dev/null | wc -l)

if [ "$TRACK_COUNT" -lt 3 ]; then
    echo "ERROR: Expected 3 audio tracks, found $TRACK_COUNT"
    exit 1
fi

echo "✓ Test video created with $TRACK_COUNT audio tracks"

# Show audio track info for debugging
echo "Audio track information:"
ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=language,title \
        -of default=noprint_wrappers=1 test_multi_audio.mkv 2>/dev/null || true

chown ga:ga test_multi_audio.mkv

# Reset VLC audio track preference to ensure it starts with default (track 0)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    sed -i '/^audio-track=/d' "$VLC_RC"
    sed -i '/^alsa-audio-device=/d' "$VLC_RC"
fi

# Launch VLC with RC interface and the multi-audio video
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 /home/ga/Videos/test_multi_audio.mkv > /tmp/vlc_audio_track_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_audio_track_task.log
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
    echo "Waiting for RC interface... ($i/10)"
    sleep 1
done

# Verify RC interface is working
if ! echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
    echo "WARNING: RC interface may not be fully ready"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "✓ VLC window focused (ID: $wid)"
fi

# Query current audio track
echo "Checking default audio track..."
CURRENT_TRACK=$(echo "atrack" | nc -w 2 localhost 9999 2>/dev/null | grep -oP '(?:audio track:|>)\s*\K[\d-]+' | head -1 || echo "unknown")
echo "Current audio track: $CURRENT_TRACK (should be 0 or 1 = Japanese by default)"

# Give VLC a moment to fully initialize
sleep 2

echo "=== Select Audio Track Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing test_multi_audio.mkv with Japanese audio (Track 1/index 0)"
echo "  2. The video has 3 audio tracks:"
echo "     - Track 1 (index 0): Japanese - DEFAULT"
echo "     - Track 2 (index 1): English Dub - TARGET"
echo "     - Track 3 (index 2): English Audio Description"
echo "  3. Switch to Track 2 (English Dub) using:"
echo "     - Menu: Audio → Audio Track → Track 2 (English Dub)"
echo "     - Keyboard: Press 'b' to cycle through tracks until English Dub"
echo "     - Right-click: Context menu → Audio → Audio Track"
echo "  4. Verify audio changed from lower pitch (440Hz) to higher pitch (523Hz)"
echo ""
echo "File: /home/ga/Videos/test_multi_audio.mkv"
echo "Target: Track 2 (English Dub) or audio track index 1"