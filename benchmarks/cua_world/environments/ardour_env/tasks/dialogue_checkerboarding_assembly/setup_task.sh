#!/bin/bash
echo "=== Setting up dialogue_checkerboarding_assembly task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances safely
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Ensure clean working directory and backup
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
    echo "Created clean session backup"
fi

if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Make sure the source audio exists (using narration from env)
SAMPLES_DIR="/home/ga/Audio/samples"
if [ ! -f "$SAMPLES_DIR/narration.wav" ]; then
    echo "WARNING: narration.wav missing, falling back to any available wav"
    FALLBACK=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
    if [ -n "$FALLBACK" ]; then
        cp "$FALLBACK" "$SAMPLES_DIR/narration.wav"
        chown ga:ga "$SAMPLES_DIR/narration.wav"
    fi
fi

# Create editor notes for quick reference
cat > /home/ga/Audio/dialogue_notes.txt << 'NOTES'
DIALOGUE EDITOR NOTES - Scene 4 Checkerboarding
================================================

Source Media: /home/ga/Audio/samples/narration.wav
Frame Rate / Time: 44.1 kHz session

INSTRUCTIONS:
1. Import narration.wav to a new track named "Raw Scene".
   - MUST start exactly at 0:00.000.
2. Create tracks: "Character A" and "Character B"
3. Create bus: "Dia Bus"
4. Split the raw audio clip at these exact times:
   - 0:08.000
   - 0:15.000
   - 0:22.000
5. Distribute segments (without shifting their time!):
   - Segments 1 & 3 -> Character A
   - Segments 2 & 4 -> Character B
6. Route both Character A & B outputs to "Dia Bus".
7. Clean up by deleting or completely muting the "Raw Scene" track.
8. Save your session.
NOTES
chown ga:ga /home/ga/Audio/dialogue_notes.txt

# Record baseline metadata
if [ -f "$SESSION_FILE" ]; then
    INITIAL_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_MTIME" > /tmp/initial_mtime
fi

date +%s > /tmp/task_start_timestamp

# Launch Ardour
launch_ardour_session "$SESSION_FILE"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="