#!/bin/bash
echo "=== Setting up telephone_futz_eq_design task ==="

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

# Ensure samples directory and narration file exist
SAMPLES_DIR="/home/ga/Audio/samples"
if [ ! -d "$SAMPLES_DIR" ]; then
    mkdir -p "$SAMPLES_DIR"
    chown ga:ga "$SAMPLES_DIR"
fi

# If narration.wav is missing, try to link/copy from other available samples
if [ ! -f "$SAMPLES_DIR/narration.wav" ]; then
    for f in "$SAMPLES_DIR"/art_of_war.wav "$SAMPLES_DIR"/good_morning.wav "$SAMPLES_DIR"/moonlight_sonata.wav; do
        if [ -f "$f" ]; then
            cp "$f" "$SAMPLES_DIR/narration.wav"
            chown ga:ga "$SAMPLES_DIR/narration.wav"
            echo "Created narration.wav from $f"
            break
        fi
    done
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