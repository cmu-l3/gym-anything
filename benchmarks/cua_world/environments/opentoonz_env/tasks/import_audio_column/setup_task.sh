#!/bin/bash
set -e
echo "=== Setting up import_audio_column task ==="

# 1. Create necessary directories
su - ga -c "mkdir -p /home/ga/OpenToonz/audio"
su - ga -c "mkdir -p /home/ga/OpenToonz/projects/audio_sync_scene"

# 2. Generate Real Audio Data (Broadcast Standard 1kHz Tone)
# This ensures we are using 'real' data properties (valid headers, duration)
# rather than an empty dummy file.
AUDIO_FILE="/home/ga/OpenToonz/audio/reference_dialogue.wav"
if [ ! -f "$AUDIO_FILE" ]; then
    echo "Generating broadcast reference audio..."
    # Generate 5 seconds of 1kHz sine wave at 44.1kHz
    su - ga -c "ffmpeg -y -f lavfi -i 'sine=frequency=1000:sample_rate=44100:duration=5' -c:a pcm_s16le '$AUDIO_FILE' 2>/dev/null"
fi
echo "Audio file prepared at: $AUDIO_FILE"

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Ensure OpenToonz is running and clean
if pgrep -f opentoonz > /dev/null; then
    echo "OpenToonz is running."
else
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
    sleep 10 # Allow full initialization
fi

# 5. Reset/Ensure correct starting state
# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any startup popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="