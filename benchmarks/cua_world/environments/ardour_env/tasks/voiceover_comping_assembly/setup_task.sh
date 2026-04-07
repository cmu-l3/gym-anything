#!/bin/bash
echo "=== Setting up voiceover_comping_assembly task ==="

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

# Create vo_takes directory
su - ga -c "mkdir -p /home/ga/Audio/vo_takes"

# Find a suitable audio file for the takes
SAMPLES_DIR="/home/ga/Audio/samples"
NARRATION_SRC=""

# Prefer speech sample
for f in "$SAMPLES_DIR"/narration.wav "$SAMPLES_DIR"/art_of_war.wav "$SAMPLES_DIR"/good_morning.wav; do
    if [ -f "$f" ]; then
        NARRATION_SRC="$f"
        break
    fi
done

if [ -z "$NARRATION_SRC" ]; then
    NARRATION_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

if [ -n "$NARRATION_SRC" ]; then
    cp "$NARRATION_SRC" /home/ga/Audio/vo_takes/take1.wav
    cp "$NARRATION_SRC" /home/ga/Audio/vo_takes/take2.wav
    cp "$NARRATION_SRC" /home/ga/Audio/vo_takes/take3.wav
    chown ga:ga /home/ga/Audio/vo_takes/*.wav
    echo "Narration source: $NARRATION_SRC"
fi

# Create producer notes
cat > /home/ga/Audio/vo_takes/producer_notes.txt << 'NOTES'
VOICEOVER COMPING NOTES
Project: Radio Commercial
Date: 2026-03-10

We have three takes from the voice actor. Please assemble the final voiceover using the following sections.

1. INTRO: Use "Take 2" from 0:00 to 0:04.
2. BODY: Use "Take 1" from 0:04 to 0:12.
3. OUTRO: Use "Take 3" from 0:12 to 0:18.

INSTRUCTIONS:
- Import the three takes from /home/ga/Audio/vo_takes/
- Create a composite track named "Final VO" (or "Comp").
- Slice the specified sections from their respective takes.
- Arrange them in chronological order (Intro -> Body -> Outro) back-to-back with no gaps.
- Make sure the final composite track is the only one playing (MUTE the original take tracks, or delete the unused regions).
- Save the session.
NOTES

chown ga:ga /home/ga/Audio/vo_takes/producer_notes.txt

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="