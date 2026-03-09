#!/bin/bash
echo "=== Setting up import_audio_track task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances
kill_ardour

# Ensure the import file exists
if [ ! -f /home/ga/Audio/import_me.wav ]; then
    # Find any available sample
    for f in /home/ga/Audio/samples/*.wav; do
        if [ -f "$f" ]; then
            cp "$f" /home/ga/Audio/import_me.wav
            chown ga:ga /home/ga/Audio/import_me.wav
            break
        fi
    done
fi

# Count tracks before import (save for verification)
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
if [ -f "$SESSION_DIR/MyProject.ardour" ]; then
    TRACK_COUNT_BEFORE=$(grep -c '<Route.*default-type="audio"' "$SESSION_DIR/MyProject.ardour" 2>/dev/null || echo "0")
    echo "$TRACK_COUNT_BEFORE" > /tmp/track_count_before.txt
    echo "Tracks before import: $TRACK_COUNT_BEFORE"
fi

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_DIR/MyProject.ardour"

sleep 3

echo "=== Task setup complete ==="
echo "Agent should import /home/ga/Audio/import_me.wav into the session"
