#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Transcription Workflow Task ==="

kill_vlc ga
sleep 1

# Ensure workspace directory exists
mkdir -p /home/ga/workspace
chown -R ga:ga /home/ga/workspace

# Generate or download interview-style audio file
AUDIO_FILE="/home/ga/workspace/interview_audio.mp3"

if [ ! -f "$AUDIO_FILE" ]; then
    echo "Generating interview audio file..."
    # Generate a 3-minute audio file (enough for testing, not too large)
    # Using pink noise as placeholder for speech
    su - ga -c "ffmpeg -f lavfi -i 'anoisesrc=d=180:c=pink:r=44100:a=0.1' \
           -af 'volume=0.3' \
           -c:a libmp3lame -b:a 128k \
           '$AUDIO_FILE' -y > /tmp/ffmpeg_audio.log 2>&1" || {
        echo "ERROR: Failed to generate audio file"
        cat /tmp/ffmpeg_audio.log
        exit 1
    }
    echo "✅ Audio file generated"
fi

# Backup existing VLC config if it exists
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

mkdir -p "$VLC_CONFIG_DIR"
chown -R ga:ga "$VLC_CONFIG_DIR"

if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "$VLC_RC.backup.$(date +%s)"
    echo "Backed up existing VLC config"
fi

# Reset VLC config to default jump intervals
# This ensures agent must actually configure it
cat > "$VLC_RC" << 'EOF'
[qt]
qt-privacy-ask=0
qt-start-minimized=0

[core]
# Default jump intervals (agent needs to change short-jump-size to ~3)
short-jump-size=10
medium-jump-size=60
long-jump-size=300

# Audio settings
audio-volume=256

# Interface settings
loop=0
repeat=0
EOF

chown ga:ga "$VLC_RC"
echo "✅ VLC config reset to defaults (short-jump-size=10)"

# Launch VLC with audio file
echo "Launching VLC with interview audio..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show '$AUDIO_FILE' > /tmp/vlc_transcription_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_transcription_task.log
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

# Pause playback so audio isn't distracting
echo "Pausing playback..."
sleep 1
su - ga -c "DISPLAY=:1 xdotool key space" || true

echo "=== Configure Transcription Workflow Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. VLC is playing interview audio (currently paused)"
echo "  2. Configure short jump interval to ~3 seconds:"
echo "     • Open: Tools → Preferences (Ctrl+P)"
echo "     • Click 'All' at bottom-left to show advanced settings"
echo "     • Navigate to: Interface → Hotkeys"
echo "     • Or search for 'short jump' in the search box"
echo "     • Find 'Short jump length' or similar"
echo "     • Change value from 10 to 3 seconds"
echo "  3. Click 'Save' button"
echo "  4. Configuration will be saved to ~/.config/vlc/vlcrc"
echo ""
echo "🎯 Goal: Set short jump interval to 2-5 seconds (3 is ideal)"
echo "📁 Audio file: /home/ga/workspace/interview_audio.mp3"
echo "⚙️  Config file: /home/ga/.config/vlc/vlcrc"