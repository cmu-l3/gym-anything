#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Practice Loop Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

VIDEOS_DIR="/home/ga/Videos"
CONFIG_DIR="/home/ga/.config/vlc"
LOG_FILE="/tmp/vlc_practice_loop_task.log"

# Ensure directories exist
mkdir -p "$VIDEOS_DIR" "$CONFIG_DIR"
chown -R ga:ga "$VIDEOS_DIR" "$CONFIG_DIR"

# Check if practice song already exists
PRACTICE_SONG="$VIDEOS_DIR/practice_song.mp4"

if [ ! -f "$PRACTICE_SONG" ]; then
    echo "Generating practice song with guitar solo section..."
    
    # Generate practice song as user 'ga'
    su - ga -c "cd /home/ga/Videos && bash -c '
        # Create 3-minute audio track with distinct sections
        # Main song: 0:00-1:34 (94s) - Base frequency 440Hz
        # Solo: 1:34-1:58 (24s) - Higher frequency pattern 880Hz + variations
        # Outro: 1:58-3:00 (62s) - Back to 440Hz
        
        # Generate base section (0-94s)
        ffmpeg -y -f lavfi -i \"sine=frequency=440:duration=94\" -f lavfi -i \"sine=frequency=554:duration=94\" \
            -filter_complex \"[0][1]amix=inputs=2:duration=longest\" /tmp/base.wav 2>/dev/null
        
        # Generate solo section (24s) with varying frequencies to simulate guitar solo
        ffmpeg -y -f lavfi -i \"sine=frequency=880:duration=6\" -f lavfi -i \"sine=frequency=988:duration=6\" \
            -f lavfi -i \"sine=frequency=1047:duration=6\" -f lavfi -i \"sine=frequency=784:duration=6\" \
            -filter_complex \"[0][1][2][3]concat=n=4:v=0:a=1\" /tmp/solo.wav 2>/dev/null
        
        # Generate outro section (62s)
        ffmpeg -y -f lavfi -i \"sine=frequency=440:duration=62\" -f lavfi -i \"sine=frequency=554:duration=62\" \
            -filter_complex \"[0][1]amix=inputs=2:duration=longest\" /tmp/outro.wav 2>/dev/null
        
        # Concatenate all sections
        ffmpeg -y -i /tmp/base.wav -i /tmp/solo.wav -i /tmp/outro.wav \
            -filter_complex \"[0][1][2]concat=n=3:v=0:a=1\" /tmp/full_song.wav 2>/dev/null
        
        # Create video with audio (black background with text overlay)
        ffmpeg -y -f lavfi -i \"color=c=black:s=1280x720:d=180\" -i /tmp/full_song.wav \
            -vf \"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Practice Song':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2-100,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Solo Section\\: 1\\:34 - 1\\:58':fontcolor=yellow:fontsize=32:x=(w-text_w)/2:y=(h-text_h)/2+50\" \
            -c:v libx264 -preset fast -c:a aac -shortest practice_song.mp4 2>/dev/null
        
        # Cleanup temp files
        rm -f /tmp/base.wav /tmp/solo.wav /tmp/outro.wav /tmp/full_song.wav
        
        echo \"Practice song generated successfully\"
    '" >> "$LOG_FILE" 2>&1
    
    if [ ! -f "$PRACTICE_SONG" ]; then
        echo "ERROR: Failed to generate practice song"
        exit 1
    fi
    
    echo "✅ Practice song created: practice_song.mp4 (3:00, solo at 1:34-1:58)"
else
    echo "✅ Practice song already exists"
fi

# Reset VLC config to defaults (clear any existing A-B repeat or speed settings)
echo "Resetting VLC configuration..."
VLC_RC="$CONFIG_DIR/vlcrc"

su - ga -c "cat > $VLC_RC << 'VLCRC'
# VLC configuration for practice loop task
[qt]
qt-privacy-ask=0

[core]
# Default settings - agent will configure these
rate=1.0
input-repeat=0
audio-time-stretch=1
VLCRC
"

echo "VLC config reset to defaults"

# Launch VLC with RC interface enabled
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 --start-paused '$PRACTICE_SONG' > $LOG_FILE 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat "$LOG_FILE"
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

# Unpause to initialize video output
echo "Initializing playback..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 2

# Pause again
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

# Seek to start
echo "Seeking to beginning..."
su - ga -c "DISPLAY=:1 xdotool key ctrl+Home" || true
sleep 0.5

echo "=== Practice Loop Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Practice song is loaded (3 min, solo at 1:34-1:58)"
echo "  2. Configure A-B repeat loop:"
echo "     a. Seek to ~1:34 (94 seconds) - solo start"
echo "     b. Set Point A (Playback → A-B Repeat → Set A)"
echo "     c. Seek to ~1:58 (118 seconds) - solo end"
echo "     d. Set Point B (Playback → A-B Repeat → Set B)"
echo "  3. Adjust playback speed to 0.70x:"
echo "     - Playback → Speed → Slower (or press [ key 3 times)"
echo "     - Or: Playback → Speed → Custom → 0.70"
echo "  4. Enable time-stretching (pitch preservation):"
echo "     - Tools → Preferences → Audio → Enable time-stretching"
echo "     - Or: Tools → Preferences → Show all → Audio → Time-stretching audio"
echo "  5. Play and verify loop repeats at 70% speed with normal pitch"