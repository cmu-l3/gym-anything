#!/bin/bash
echo "=== Setting up commercial_audio_bed_edit task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Kill any existing Ardour instances
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Ensure we have a clean session backup
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
    echo "Created clean session backup"
fi

# Restore clean session to ensure predictable starting state
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Ensure import file is ready
SAMPLES_DIR="/home/ga/Audio/samples"
IMPORT_TARGET="/home/ga/Audio/import_me.wav"

if [ ! -f "$IMPORT_TARGET" ]; then
    # Prefer speech sample if available
    if [ -f "$SAMPLES_DIR/narration.wav" ]; then
        cp "$SAMPLES_DIR/narration.wav" "$IMPORT_TARGET"
    elif [ -f "$SAMPLES_DIR/art_of_war.wav" ]; then
        cp "$SAMPLES_DIR/art_of_war.wav" "$IMPORT_TARGET"
    else
        # Fallback to any wav
        FALLBACK=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
        if [ -n "$FALLBACK" ]; then
            cp "$FALLBACK" "$IMPORT_TARGET"
        fi
    fi
    chown ga:ga "$IMPORT_TARGET"
fi

echo "Voiceover import target ready at: $IMPORT_TARGET"

# Launch Ardour with the session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="