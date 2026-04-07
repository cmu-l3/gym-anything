#!/bin/bash
echo "=== Setting up film_scoring_session_setup task ==="

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

# Create film project directory
su - ga -c "mkdir -p /home/ga/Audio/film_project"

# Create the spotting notes document
cat > /home/ga/Audio/film_project/spotting_notes.txt << 'NOTES'
===============================================================
SPOTTING NOTES - "Urban Renewal" Documentary
Director: James Okafor
Music Director Session Prep
Date: 2024-12-08
===============================================================

FILM DETAILS:
  Total runtime: 4 minutes
  Session sample rate: 44100 Hz

TEMPO AND METER:
  Tempo: 92 BPM
  Time signature: 4/4

REQUIRED TRACKS (create in this order):
  1. "Strings"        - pan 30% left
  2. "Piano"          - pan center
  3. "Ambient Synth"  - pan 20% right
  4. "Percussion"     - pan center
  5. "Dialogue Ref"   - pan center, MUTED (reference only)

SCENE MARKERS (place at these timecodes):
  "Opening Titles"   - 00:00:00  (sample 0)
  "Interview 1"      - 00:00:30  (sample 1323000)
  "B-Roll Montage"   - 00:01:15  (sample 3307500)
  "Interview 2"      - 00:02:00  (sample 5292000)
  "Closing"          - 00:03:00  (sample 7938000)
  "End Credits"      - 00:03:30  (sample 9261000)

REFERENCE AUDIO:
  Import /home/ga/Audio/samples/moonlight_sonata.wav onto the
  "Dialogue Ref" track, starting at the "Interview 1" marker
  position (sample 1323000 / timecode 00:00:30).

NOTES FOR MUSIC DIRECTOR:
  - The Strings track carries the main melodic theme
  - Piano provides harmonic foundation
  - Ambient Synth creates atmospheric texture for B-Roll sections
  - Percussion enters only during Interview 2 and Closing
  - Keep Dialogue Ref muted; it is for timing reference only
===============================================================
NOTES

chown -R ga:ga /home/ga/Audio/film_project

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
echo "Spotting notes at /home/ga/Audio/film_project/spotting_notes.txt"
