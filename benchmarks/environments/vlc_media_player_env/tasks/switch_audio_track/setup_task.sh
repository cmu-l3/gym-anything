#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Switch Audio Track Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate multi-audio track video file
echo "Generating multilingual video with 2 audio tracks..."

VIDEO_FILE="/home/ga/Videos/multilang_sample.mp4"

# Check if ffmpeg is available (should be from environment setup)
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found, cannot generate test video"
    exit 1
fi

# Create a 30-second video with two distinct audio tracks
# Track 0 (English): 440 Hz tone (A note)
# Track 1 (Japanese): 880 Hz tone (A note, one octave higher)
# Different frequencies make tracks audibly distinguishable

ffmpeg -y \
    -f lavfi -i "color=c=blue:s=1280x720:d=30,drawtext=text='Multi-Language Video':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
    -f lavfi -i "sine=frequency=440:duration=30" \
    -f lavfi -i "sine=frequency=880:duration=30" \
    -map 0:v -map 1:a -map 2:a \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 30 \
    -c:a:0 aac -b:a:0 128k -ac:a:0 2 \
    -c:a:1 aac -b:a:1 128k -ac:a:1 2 \
    -metadata:s:a:0 language=eng -metadata:s:a:0 title="English" \
    -metadata:s:a:1 language=jpn -metadata:s:a:1 title="Japanese" \
    -t 30 \
    "$VIDEO_FILE" \
    > /tmp/ffmpeg_multilang.log 2>&1

if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Failed to generate video file"
    cat /tmp/ffmpeg_multilang.log
    exit 1
fi

# Verify the video has 2 audio tracks
echo "Verifying audio tracks..."
TRACK_COUNT=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$VIDEO_FILE" 2>/dev/null | wc -l)

if [ "$TRACK_COUNT" -lt 2 ]; then
    echo "ERROR: Video does not have 2 audio tracks (found: $TRACK_COUNT)"
    ffprobe -v error -show_streams "$VIDEO_FILE"
    exit 1
fi

echo "✅ Video created with $TRACK_COUNT audio tracks"

# List track details for debugging
ffprobe -v error -select_streams a -show_entries stream=index,codec_name,codec_type,channels -of json "$VIDEO_FILE" > /tmp/audio_tracks_info.json
echo "Audio track details:"
cat /tmp/audio_tracks_info.json

# Set proper permissions
chown ga:ga "$VIDEO_FILE"
chmod 644 "$VIDEO_FILE"

# Reset VLC config to ensure Track 1 (English) is default
# This ensures the agent must actively switch tracks
echo "Resetting VLC configuration..."
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc/

# Remove any existing audio track preferences
if [ -f "$VLC_RC" ]; then
    sed -i '/^audio-track=/d' "$VLC_RC"
    sed -i '/^audio-track-id=/d' "$VLC_RC"
fi

# Create/update config with defaults
cat >> "$VLC_RC" <<'EOF'

# Audio track defaults (Track 1/English)
audio-track=0
audio-track-id=0

# Privacy and UI settings
[qt]
qt-privacy-ask=0
qt-start-minimized=0
EOF

chown -R ga:ga /home/ga/.config/vlc/

echo "✅ VLC configuration reset to default (Track 1/English)"

# Launch VLC with the multilingual video and RC interface
echo "Launching VLC with multilingual video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$VIDEO_FILE' > /tmp/vlc_audio_track_task.log 2>&1 &"

# Wait for VLC to start
if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_audio_track_task.log
    exit 1
fi

# Wait for window to appear
if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_audio_track_task.log
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "✅ RC interface ready"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "⚠️ RC interface did not become ready (continuing anyway)"
    fi
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
else
    echo "⚠️ Could not get VLC window ID"
fi

# Verify audio track via RC interface (should be Track 1/0 initially)
echo "Verifying initial audio track..."
INITIAL_TRACK=$(echo "atrack" | nc -w 2 localhost 9999 2>/dev/null | grep -oP '>\s*\K[-\d]+' | head -1 || echo "unknown")
echo "Initial audio track: $INITIAL_TRACK"

echo "=== Switch Audio Track Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. VLC is now playing a video with 2 audio tracks"
echo "  2. Current track: Track 1 (English) - 440 Hz tone"
echo "  3. Target track: Track 2 (Japanese) - 880 Hz tone (higher pitch)"
echo "  4. To switch:"
echo "     a. Click 'Audio' in the menu bar"
echo "     b. Hover over 'Audio Track'"
echo "     c. Select 'Track 2 - [Japanese]' (or just 'Track 2')"
echo "  5. You should hear a higher-pitched tone when switched correctly"
echo ""
echo "Hint: The audio track menu shows all available tracks with checkmarks on the active one"