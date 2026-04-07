#!/bin/bash
echo "=== Setting up game_audio_seamless_loop task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Create backup of clean session on first run
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
    echo "Created clean session backup"
fi

# Restore clean session
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Ensure the import target is EXACTLY 30 seconds for mathematical precision
SAMPLES_DIR="/home/ga/Audio/samples"
SOURCE_AUDIO=""

# Prefer a continuous track like narration or sonata
for f in "$SAMPLES_DIR"/narration.wav "$SAMPLES_DIR"/moonlight_sonata.wav; do
    if [ -f "$f" ]; then
        SOURCE_AUDIO="$f"
        break
    fi
done

# Fallback
if [ -z "$SOURCE_AUDIO" ]; then
    SOURCE_AUDIO=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

echo "Using source audio: $SOURCE_AUDIO"

# Force exact 30 second duration using ffmpeg
if [ -n "$SOURCE_AUDIO" ]; then
    # Create the import_me.wav file exactly 30 seconds long, 44.1kHz
    ffmpeg -y -i "$SOURCE_AUDIO" -t 30 -ar 44100 -ac 2 /home/ga/Audio/import_me.wav 2>/dev/null || \
        cp "$SOURCE_AUDIO" /home/ga/Audio/import_me.wav
    chown ga:ga /home/ga/Audio/import_me.wav
else
    echo "WARNING: No source audio found!"
fi

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_MTIME" > /tmp/initial_session_mtime
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Target audio file: /home/ga/Audio/import_me.wav (exactly 30 seconds)"