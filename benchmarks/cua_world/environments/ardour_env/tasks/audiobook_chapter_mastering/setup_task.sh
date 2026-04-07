#!/bin/bash
echo "=== Setting up audiobook_chapter_mastering task ==="

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

# Create audiobook directories
su - ga -c "mkdir -p /home/ga/Audio/audiobook_raw"
su - ga -c "mkdir -p /home/ga/Audio/audiobook_export"
rm -f /home/ga/Audio/audiobook_export/*.wav 2>/dev/null || true

# Find a suitable audio file for the narration
SAMPLES_DIR="/home/ga/Audio/samples"
NARRATION_SRC=""

# Prefer speech sample (art_of_war), fall back to any available
for f in "$SAMPLES_DIR"/art_of_war.wav "$SAMPLES_DIR"/good_morning.wav "$SAMPLES_DIR"/moonlight_sonata.wav; do
    if [ -f "$f" ]; then
        NARRATION_SRC="$f"
        break
    fi
done

# Fallback
if [ -z "$NARRATION_SRC" ]; then
    NARRATION_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

if [ -n "$NARRATION_SRC" ]; then
    cp "$NARRATION_SRC" /home/ga/Audio/audiobook_raw/narration_full.wav
    chown ga:ga /home/ga/Audio/audiobook_raw/narration_full.wav
    echo "Narration source: $NARRATION_SRC"
fi

# Create chapter plan document
cat > /home/ga/Audio/audiobook_raw/chapter_plan.txt << 'PLAN'
================================================================
AUDIOBOOK PRODUCTION SHEET
Title: "The Art of Strategic Thinking"
Author: Margaret Chen
Narrator: David Okonjo
Publisher: Clearwater Publishing
================================================================

ACX SUBMISSION REQUIREMENTS:
  - Format: WAV, 44.1 kHz, 16-bit, mono or stereo
  - Each chapter exported as a separate file
  - 0.5 to 1 second of room tone (silence) at beginning and end
  - Consistent levels: peak between -6 dB and -3 dB
  - No excessive background noise

CHAPTER BREAKDOWN:
  The narration recording runs approximately 30 seconds total.
  Segment into 3 chapters as follows:

  Chapter 1: "Introduction"
    - Start: 0:00 (sample 0)
    - End:   0:10 (sample 441000)
    - Export filename: ch01_introduction.wav

  Chapter 2: "First Principles"
    - Start: 0:10 (sample 441000)
    - End:   0:20 (sample 882000)
    - Export filename: ch02_first_principles.wav

  Chapter 3: "Strategic Framework"
    - Start: 0:20 (sample 882000)
    - End:   0:30 (sample 1323000)
    - Export filename: ch03_strategic_framework.wav

SESSION SETUP:
  - Rename the main audio track to: "Narration - Strategic Thinking"
  - Place chapter markers at each chapter boundary
  - Set track gain to achieve -3 dB to -6 dB peak levels

EXPORT DIRECTORY: /home/ga/Audio/audiobook_export/

QUALITY CHECKLIST:
  [ ] Track renamed appropriately
  [ ] Chapter markers placed at correct positions
  [ ] Gain adjusted for ACX compliance
  [ ] 3 chapter WAV files exported
  [ ] Files are non-silent and properly trimmed
================================================================
PLAN

chown ga:ga /home/ga/Audio/audiobook_raw/chapter_plan.txt

# Record baseline state
SESSION_FILE_PATH="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
if [ -f "$SESSION_FILE_PATH" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    INITIAL_MARKER_COUNT=$(grep -c '<Location.*IsMark' "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
    echo "$INITIAL_MARKER_COUNT" > /tmp/initial_marker_count
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Narration and chapter plan in /home/ga/Audio/audiobook_raw/"
