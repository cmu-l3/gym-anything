#!/bin/bash
echo "=== Setting up vocal_stutter_edit task ==="

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

# Create export directory
su - ga -c "mkdir -p /home/ga/Audio/export"
rm -f /home/ga/Audio/export/*.wav 2>/dev/null || true

# Check if narration.wav exists, otherwise use a fallback
SAMPLES_DIR="/home/ga/Audio/samples"
if [ ! -f "$SAMPLES_DIR/narration.wav" ]; then
    # find any wav and copy it to narration.wav
    FALLBACK=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
    if [ -n "$FALLBACK" ]; then
        cp "$FALLBACK" "$SAMPLES_DIR/narration.wav"
        chown ga:ga "$SAMPLES_DIR/narration.wav"
    fi
fi

# Record baseline state
SESSION_FILE_PATH="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
if [ -f "$SESSION_FILE_PATH" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="