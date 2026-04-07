#!/bin/bash
echo "=== Setting up HIIT Workout Assembly task ==="

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

# Ensure samples are available
if [ ! -f "/home/ga/Audio/samples/moonlight_sonata.wav" ] || [ ! -f "/home/ga/Audio/samples/narration.wav" ]; then
    echo "WARNING: Required samples missing. Attempting to copy fallbacks..."
    mkdir -p /home/ga/Audio/samples
    # Create dummy files if nothing else exists (for testing purposes, though install_ardour.sh provides real ones)
    find /home/ga/Audio -name "*.wav" -type f | head -2 | while read f; do
        cp "$f" /home/ga/Audio/samples/
    done
fi

# Generate the brief file for the agent's reference
cat > /home/ga/Audio/hiit_brief.txt << 'BRIEF'
=======================================================
HIIT INTERVAL MIX - PRODUCTION BRIEF
=======================================================
Format: 50-second standard 20/10 interval.

1. TRACKS:
   - Rename default track to "Music"
   - Create new track "Voice Cues"

2. TIMELINE (Music):
   - 0.0s to 20.0s: Music plays (Work 1)
   - 20.0s to 30.0s: STRICT SILENCE (Rest gap)
   - 30.0s to 50.0s: Music plays (Work 2)

3. TIMELINE (Voice Cues):
   - 18.0s: Place a short snippet of narration here (cues the rest)
   - 28.0s: Place another snippet here (cues next work)

4. MIX LEVELS:
   - Music track: -6 dB (pushed back)
   - Voice Cues track: +3 dB (prominent)

5. MARKERS:
   - "Work 1" at 0.0s
   - "Rest" at 20.0s
   - "Work 2" at 30.0s

Save the session when finished.
=======================================================
BRIEF
chown ga:ga /home/ga/Audio/hiit_brief.txt

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_MTIME" > /tmp/initial_session_mtime
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="