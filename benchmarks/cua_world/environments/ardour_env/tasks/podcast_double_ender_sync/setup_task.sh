#!/bin/bash
echo "=== Setting up podcast_double_ender_sync task ==="

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

# Create podcast raw directory
su - ga -c "mkdir -p /home/ga/Audio/podcast_raw"

# Generate the exact double-ender audio files using SoX
echo "Generating synchronized double-ender recordings..."

# Find a source voice recording (prefer narration)
NARRATION_SRC="/home/ga/Audio/samples/narration.wav"
if [ ! -f "$NARRATION_SRC" ]; then
    NARRATION_SRC=$(find /home/ga/Audio/samples -name "*.wav" -type f | head -1)
fi

# Force narration to mono and exactly 30 seconds for consistency
sox "$NARRATION_SRC" -c 1 /tmp/mono_speech.wav trim 0 30 2>/dev/null || true

# Generate sync beep (1000Hz sine wave, 0.5s)
sox -n -r 44100 -c 1 /tmp/beep.wav synth 0.5 sine 1000 vol -10dB 2>/dev/null || true

# Generate precise silences
sox -n -r 44100 -c 1 /tmp/sil2.wav trim 0 2.0 2>/dev/null || true
sox -n -r 44100 -c 1 /tmp/sil65.wav trim 0 6.5 2>/dev/null || true
sox -n -r 44100 -c 1 /tmp/sil75.wav trim 0 7.5 2>/dev/null || true

# Host file: 2.0s silence + 0.5s beep + 7.5s silence + Speech
# Beep at 2.0s. Speech at 10.0s.
sox /tmp/sil2.wav /tmp/beep.wav /tmp/sil75.wav /tmp/mono_speech.wav /home/ga/Audio/podcast_raw/host_local.wav 2>/dev/null || true

# Guest file: 6.5s silence + 0.5s beep + 7.5s silence + Speech
# Beep at 6.5s. Speech at 14.5s.
sox /tmp/sil65.wav /tmp/beep.wav /tmp/sil75.wav /tmp/mono_speech.wav /home/ga/Audio/podcast_raw/guest_local.wav 2>/dev/null || true

chown -R ga:ga /home/ga/Audio/podcast_raw
chmod 644 /home/ga/Audio/podcast_raw/*.wav

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Host and Guest audio files generated in /home/ga/Audio/podcast_raw/"