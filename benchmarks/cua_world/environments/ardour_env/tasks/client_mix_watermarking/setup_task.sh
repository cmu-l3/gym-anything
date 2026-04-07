#!/bin/bash
echo "=== Setting up client_mix_watermarking task ==="

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

# Create client delivery directory
su - ga -c "mkdir -p /home/ga/Audio/client_delivery"
rm -f /home/ga/Audio/client_delivery/*.wav 2>/dev/null || true

# Prepare realistic audio samples
SAMPLES_DIR="/home/ga/Audio/samples"
PIANO_SRC="$SAMPLES_DIR/moonlight_sonata.wav"
WATERMARK_SRC="$SAMPLES_DIR/narration.wav"

# Fallback in case samples are missing
if [ ! -f "$PIANO_SRC" ]; then
    PIANO_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi
if [ ! -f "$WATERMARK_SRC" ]; then
    WATERMARK_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | tail -1)
fi

# Generate the 30-second piano mix and 2-second watermark snippet
ffmpeg -y -i "$PIANO_SRC" -t 30 -ar 44100 -ac 2 /home/ga/Audio/client_delivery/piano_mix.wav 2>/dev/null || \
    cp "$PIANO_SRC" /home/ga/Audio/client_delivery/piano_mix.wav

ffmpeg -y -i "$WATERMARK_SRC" -t 2 -ar 44100 -ac 1 /home/ga/Audio/client_delivery/watermark.wav 2>/dev/null || \
    cp "$WATERMARK_SRC" /home/ga/Audio/client_delivery/watermark.wav

chown -R ga:ga /home/ga/Audio/client_delivery

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing clean session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Audio resources created at /home/ga/Audio/client_delivery/"