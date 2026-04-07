#!/bin/bash
echo "=== Setting up live_session_prep task ==="

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

# Ensure the import file exists
SAMPLES_DIR="/home/ga/Audio/samples"
IMPORT_SRC=""
for f in "$SAMPLES_DIR"/art_of_war.wav "$SAMPLES_DIR"/moonlight_sonata.wav "$SAMPLES_DIR"/good_morning.wav; do
    if [ -f "$f" ]; then
        IMPORT_SRC="$f"
        break
    fi
done

if [ -z "$IMPORT_SRC" ]; then
    IMPORT_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

if [ -n "$IMPORT_SRC" ]; then
    cp "$IMPORT_SRC" /home/ga/Audio/import_me.wav
    chown ga:ga /home/ga/Audio/import_me.wav
    echo "Import source prepared: /home/ga/Audio/import_me.wav"
fi

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="