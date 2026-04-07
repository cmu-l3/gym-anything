#!/bin/bash
echo "=== Setting up SMPTE Audio Spotting task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances safely
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Create backup of clean session on first run
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
    echo "Created clean session backup"
fi

# Restore clean session to guarantee a fresh start
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Ensure the required audio sample is present
if [ ! -f "/home/ga/Audio/samples/narration.wav" ]; then
    echo "WARNING: /home/ga/Audio/samples/narration.wav not found. Attempting to provide fallback."
    mkdir -p /home/ga/Audio/samples
    # Look for any .wav in samples to use as a fallback, or create a dummy
    FALLBACK=$(ls /home/ga/Audio/samples/*.wav 2>/dev/null | head -1)
    if [ -n "$FALLBACK" ]; then
        cp "$FALLBACK" /home/ga/Audio/samples/narration.wav
    else
        # Extremely basic fallback if none exist (so task doesn't completely break)
        su - ga -c "sox -n -r 44100 -c 1 /home/ga/Audio/samples/narration.wav trim 0 30" 2>/dev/null || true
    fi
fi
chown ga:ga /home/ga/Audio/samples/narration.wav

# Record task start timestamp for anti-gaming (verifying session was saved during task)
date +%s > /tmp/task_start_time.txt

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

# Allow UI to stabilize
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="