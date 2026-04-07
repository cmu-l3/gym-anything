#!/bin/bash
echo "=== Setting up guided_meditation_pacing task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

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

# Restore clean session to ensure predictable starting state
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Prepare the export directory and clean old artifacts
su - ga -c "mkdir -p /home/ga/Audio/meditation_export"
rm -f /home/ga/Audio/meditation_export/*.wav 2>/dev/null || true

# Verify that our source audio files exist (provided by ardour_env installation)
SAMPLES_DIR="/home/ga/Audio/samples"
if [ ! -f "$SAMPLES_DIR/narration.wav" ] || [ ! -f "$SAMPLES_DIR/moonlight_sonata.wav" ]; then
    echo "WARNING: Required samples not found! Attempting to generate fallbacks..."
    su - ga -c "mkdir -p $SAMPLES_DIR"
    # Create simple tones if the real files are somehow missing
    sox -n -r 44100 -c 1 "$SAMPLES_DIR/narration.wav" synth 30 sine 440 2>/dev/null || true
    sox -n -r 44100 -c 2 "$SAMPLES_DIR/moonlight_sonata.wav" synth 60 sine 300 2>/dev/null || true
fi

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot showing clean workspace
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="