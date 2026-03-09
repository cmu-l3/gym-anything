#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Mono Compatibility Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure directories exist
mkdir -p /home/ga/Music
mkdir -p /home/ga/.config/vlc
chown -R ga:ga /home/ga/Music
chown -R ga:ga /home/ga/.config/vlc

# Generate stereo podcast audio file with distinct L/R channels
# This simulates a podcast with stereo music and panned effects
# Left channel: 440 Hz (A4 note)
# Right channel: 554 Hz (C#5 note)
# When downmixed to mono, both frequencies should be heard together
echo "Generating stereo podcast audio..."
if [ ! -f /home/ga/Music/podcast_episode.mp3 ]; then
    ffmpeg -f lavfi -i "sine=frequency=440:duration=180" \
           -f lavfi -i "sine=frequency=554:duration=180" \
           -filter_complex "[0:a][1:a]amerge=inputs=2,pan=stereo|c0<c0|c1<c1[aout]" \
           -map "[aout]" -ac 2 -ar 44100 \
           /home/ga/Music/podcast_episode.mp3 \
           -y -loglevel error
    
    if [ $? -ne 0 ]; then
        echo "WARNING: ffmpeg stereo generation failed, using simpler method..."
        # Fallback: simpler stereo generation
        ffmpeg -f lavfi -i "sine=frequency=440:duration=180" \
               -ac 2 /home/ga/Music/podcast_episode.mp3 \
               -y -loglevel error
    fi
fi

chown ga:ga /home/ga/Music/podcast_episode.mp3
chmod 644 /home/ga/Music/podcast_episode.mp3

echo "✅ Podcast audio file ready: $(ls -lh /home/ga/Music/podcast_episode.mp3)"

# Reset VLC config to ensure NO mono filters are active (default stereo)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing mono-related settings
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^mono=/d' "$VLC_RC"
    sed -i '/^stereo-to-mono=/d' "$VLC_RC"
    sed -i '/^audio-channel-mixer=/d' "$VLC_RC"
    sed -i '/^channels=/d' "$VLC_RC"
    sed -i '/^aout-channel-mixer=/d' "$VLC_RC"
    echo "✅ VLC config reset to stereo (default)"
else
    # Create minimal config
    cat > "$VLC_RC" << 'EOF'
[core]
# VLC preferences

[qt]
qt-privacy-ask=0

[audio]
audio-volume=256
# Default stereo configuration (no mono filters)
EOF
fi

chown ga:ga "$VLC_RC"
chmod 644 "$VLC_RC"

# Launch VLC with RC interface enabled for monitoring
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 /home/ga/Music/podcast_episode.mp3 > /tmp/vlc_mono_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_mono_task.log || true
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
        echo "✅ RC interface ready"
        break
    fi
    echo "RC interface not ready, waiting... ($i/10)"
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "✅ VLC window focused"
fi

# Wait for VLC to fully initialize
sleep 2

echo "=== Verify Mono Compatibility Task Setup Complete ==="
echo ""
echo "📋 TASK DESCRIPTION:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "You are a podcast producer checking mobile compatibility."
echo ""
echo "SCENARIO: Your podcast sounds great in stereo on studio monitors,"
echo "but 60% of your audience listens on mono devices (phones, smart"
echo "speakers). You need to test how it sounds in mono before publishing."
echo ""
echo "GOAL: Configure VLC to play audio in MONO mode"
echo ""
echo "📝 INSTRUCTIONS:"
echo "  1. Open Tools → Preferences (Ctrl+P)"
echo "  2. Click 'Show settings: All' at the bottom-left"
echo "  3. Navigate to Audio → Filters"
echo "  4. Check the 'Mono' checkbox to enable mono audio filter"
echo "  5. Click 'Save' to persist the configuration"
echo "  6. The audio will now play in mono for compatibility testing"
echo ""
echo "ALTERNATIVE METHODS:"
echo "  - Audio → Output modules → configure for mono"
echo "  - Use the audio-filter=mono setting"
echo ""
echo "FILE: /home/ga/Music/podcast_episode.mp3 (3 min stereo audio)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""