#!/bin/bash
echo "=== Setting up escape_room_audio_puzzle task ==="

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

# Create target directories
su - ga -c "mkdir -p /home/ga/Audio/escape_room"
rm -f /home/ga/Audio/escape_room/*.wav 2>/dev/null || true

# Ensure source files exist from environment setup
if [ ! -f "/home/ga/Audio/samples/narration.wav" ] || [ ! -f "/home/ga/Audio/samples/moonlight_sonata.wav" ]; then
    echo "WARNING: Expected sample files not found. Creating fallbacks."
    su - ga -c "mkdir -p /home/ga/Audio/samples"
    # Create simple dummy wav files using sox if needed (though env setup should provide them)
    su - ga -c "sox -n -r 44100 -c 1 /home/ga/Audio/samples/narration.wav synth 30 sine 440" 2>/dev/null || true
    su - ga -c "sox -n -r 44100 -c 2 /home/ga/Audio/samples/moonlight_sonata.wav synth 30 sine 880" 2>/dev/null || true
fi

# Create production brief
cat > /home/ga/Audio/escape_room/puzzle_brief.txt << 'BRIEF'
HAUNTED ASYLUM ESCAPE ROOM - AUDIO PUZZLE BRIEF
================================================

Puzzle Name: The Reversed Phonograph
Output File: /home/ga/Audio/escape_room/puzzle_clue.wav
Sample Rate: 44.1 kHz

Elements:
1. Distraction Track:
   - File: /home/ga/Audio/samples/moonlight_sonata.wav
   - Track Name: "Gramophone"
   - Position: Start at 0:00
   - Pan: 100% Right (Hard Right)

2. Clue Track:
   - File: /home/ga/Audio/samples/narration.wav
   - Track Name: "Hidden Message"
   - Processing: Trimmed to exactly 10 seconds AND Reversed (plays backwards)
   - Position: Start at 0:05 (5.0 seconds into the timeline)
   - Pan: 100% Left (Hard Left)

3. Timeline Markers:
   - Place a marker named "Clue Start" exactly at 0:05 where the hidden message begins.

The final exported WAV will be wired to a modified prop phonograph. When players figure out the wiring sequence, the left speaker activates and the motor reverses, revealing the hidden message.
BRIEF

chown ga:ga /home/ga/Audio/escape_room/puzzle_brief.txt

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Record task start timestamp for anti-gaming (file mtime verification)
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Target directory is /home/ga/Audio/escape_room/"