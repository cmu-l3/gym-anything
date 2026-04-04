#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Isolate Dialogue Track Task ==="

kill_vlc ga
sleep 1

# Ensure audio directory exists
mkdir -p /home/ga/Videos/audio_test
chown ga:ga /home/ga/Videos/audio_test

# Create a test video with stereo audio (dialogue center, music left-right)
# We'll create a simple stereo audio test file if it doesn't exist
TEST_VIDEO="/home/ga/Videos/audio_test/dialogue_music_mix.mp4"

if [ ! -f "$TEST_VIDEO" ]; then
    echo "Creating test video with stereo audio mix..."
    
    # Create a 20-second test video with:
    # - Center channel: sine wave (simulating dialogue)
    # - Left/Right channels: different frequencies (simulating music)
    
    # Generate center audio (mono - will be same in L and R)
    ffmpeg -f lavfi -i "sine=frequency=440:duration=20" -ac 1 /tmp/center_audio.wav > /dev/null 2>&1 || true
    
    # Generate left-right music (stereo with different content)
    ffmpeg -f lavfi -i "sine=frequency=300:duration=20" -f lavfi -i "sine=frequency=600:duration=20" \
           -filter_complex "[0:a][1:a]amerge=inputs=2[aout]" -map "[aout]" -ac 2 /tmp/stereo_music.wav > /dev/null 2>&1 || true
    
    # Mix them: center audio goes equally to L and R, music audio is added
    ffmpeg -i /tmp/center_audio.wav -i /tmp/stereo_music.wav \
           -filter_complex "[0:a]asplit=2[c1][c2];[c1][c2]amerge=inputs=2[center_stereo];[center_stereo][1:a]amix=inputs=2:duration=shortest[aout]" \
           -map "[aout]" -f lavfi -i color=c=blue:s=640x480:d=20 -c:v libx264 -c:a aac -shortest "$TEST_VIDEO" > /dev/null 2>&1 || true
    
    # Fallback: if complex mix fails, use simpler approach
    if [ ! -f "$TEST_VIDEO" ]; then
        echo "Using fallback test video creation..."
        ffmpeg -f lavfi -i color=c=blue:s=640x480:d=20 -f lavfi -i "sine=frequency=440:duration=20" \
               -c:v libx264 -c:a aac -shortest "$TEST_VIDEO" > /dev/null 2>&1 || true
    fi
    
    # Cleanup temp files
    rm -f /tmp/center_audio.wav /tmp/stereo_music.wav
    
    chown ga:ga "$TEST_VIDEO"
    echo "Test video created: $TEST_VIDEO"
fi

# Reset VLC audio filter settings to default
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing audio filter settings
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^headphone-/d' "$VLC_RC"
    sed -i '/^spatializer/d' "$VLC_RC"
    sed -i '/^stereo-mode=/d' "$VLC_RC"
    sed -i '/^audio-channel-mixer=/d' "$VLC_RC"
    echo "Audio filters reset to default"
fi

# Launch VLC with RC interface enabled and test video
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$TEST_VIDEO' > /tmp/vlc_dialogue_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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

# Wait for VLC to fully render
sleep 2

echo "=== Isolate Dialogue Track Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a video with dialogue and background music mixed in stereo"
echo "  2. Configure audio filters to isolate the center channel (dialogue)"
echo "  3. Open: Tools -> Effects and Filters (Ctrl+E)"
echo "  4. Go to: Audio Effects tab"
echo "  5. Enable one of these filters:"
echo "     a) Headphone effect with 'Dolby Surround' mode (extracts center)"
echo "     b) Spatializer with center emphasis"
echo "     c) Stereo mode manipulation to extract center content"
echo "  6. The goal is to make dialogue prominent while reducing background music"