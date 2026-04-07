#!/bin/bash
echo "=== Setting up oral_history_tape_assembly task ==="

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

# Create task directories
su - ga -c "mkdir -p /home/ga/Audio/digitization"
su - ga -c "mkdir -p /home/ga/Audio/archival_exports"
rm -f /home/ga/Audio/archival_exports/*.wav 2>/dev/null || true

# Generate the digitized tape files from a sample
SAMPLES_DIR="/home/ga/Audio/samples"
NARRATION_SRC="$SAMPLES_DIR/narration.wav"

if [ ! -f "$NARRATION_SRC" ]; then
    NARRATION_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

echo "Using source: $NARRATION_SRC for tape generation"

# Side A: 0 to 15 seconds
ffmpeg -y -i "$NARRATION_SRC" -t 15 -ar 44100 -ac 1 "/home/ga/Audio/digitization/tape_042_sideA.wav" 2>/dev/null || \
    cp "$NARRATION_SRC" "/home/ga/Audio/digitization/tape_042_sideA.wav"

# Side B: 13 to 28 seconds (creating a 2-second overlap of the same content)
ffmpeg -y -i "$NARRATION_SRC" -ss 13 -t 15 -ar 44100 -ac 1 "/home/ga/Audio/digitization/tape_042_sideB.wav" 2>/dev/null || \
    cp "$NARRATION_SRC" "/home/ga/Audio/digitization/tape_042_sideB.wav"

chown -R ga:ga /home/ga/Audio/digitization

# Create instructions document
cat > /home/ga/Audio/digitization/restoration_notes.txt << 'NOTES'
================================================================
ARCHIVAL RESTORATION NOTES
Item: Oral History Interview 042
Date Digitized: 2024-12-10
================================================================

SOURCE MATERIALS:
  - tape_042_sideA.wav (15.0 seconds)
  - tape_042_sideB.wav (15.0 seconds)

NOTES:
  The tape recorder auto-reversed during the interview. To ensure
  no audio was lost, the transfer engineer captured a 2-second 
  redundant overlap at the beginning of Side B.

RESTORATION INSTRUCTIONS:
  1. Rename the main audio track to: "Oral History Archive - Tape 042"
  2. Place Side A at the very beginning of the timeline (0:00).
  3. Place Side B on the SAME track, overlapping the end of Side A
     by exactly 2.0 seconds (i.e., Side B should start at 0:13).
  4. Place a session marker named "Tape Flip" precisely where 
     Side B begins (at 0:13) for future reference.
  5. Export the restored continuous session to:
     /home/ga/Audio/archival_exports/master_tape_042.wav

================================================================
NOTES

chown ga:ga /home/ga/Audio/digitization/restoration_notes.txt

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Record task start timestamp for anti-gaming (file mtime check)
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Digitized tapes and notes in /home/ga/Audio/digitization/"