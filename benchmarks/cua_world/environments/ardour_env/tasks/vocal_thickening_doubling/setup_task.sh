#!/bin/bash
echo "=== Setting up vocal_thickening_doubling task ==="

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

# Copy the vocal sample
SAMPLES_DIR="/home/ga/Audio/samples"
VOCAL_SRC=""

# Prefer narration/speech for vocal processing tasks
for f in "$SAMPLES_DIR"/narration.wav "$SAMPLES_DIR"/art_of_war.wav "$SAMPLES_DIR"/good_morning.wav; do
    if [ -f "$f" ]; then
        VOCAL_SRC="$f"
        break
    fi
done

# Fallback to any available audio sample
if [ -z "$VOCAL_SRC" ]; then
    VOCAL_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

if [ -n "$VOCAL_SRC" ]; then
    cp "$VOCAL_SRC" /home/ga/Audio/vocal_sample.wav
    chown ga:ga /home/ga/Audio/vocal_sample.wav
    echo "Vocal source prepped: /home/ga/Audio/vocal_sample.wav"
else
    echo "WARNING: Could not find a vocal sample in $SAMPLES_DIR"
fi

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="