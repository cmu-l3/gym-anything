#!/bin/bash
echo "=== Setting up Foley Synchronization Task ==="

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

# Restore clean session to guarantee an empty timeline
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Setup foley elements directory
su - ga -c "mkdir -p /home/ga/Audio/foley_elements"

# Copy and format a raw audio file to serve as the Foley recording
SAMPLES_DIR="/home/ga/Audio/samples"
FOLEY_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)

if [ -n "$FOLEY_SRC" ]; then
    # Ensure it's a mono 44.1kHz 30s file for consistency
    ffmpeg -y -i "$FOLEY_SRC" -t 30 -ar 44100 -ac 1 /home/ga/Audio/foley_elements/raw_footsteps.wav 2>/dev/null || \
    cp "$FOLEY_SRC" /home/ga/Audio/foley_elements/raw_footsteps.wav
    chown ga:ga /home/ga/Audio/foley_elements/raw_footsteps.wav
fi

# Create the spotting notes text file
cat > /home/ga/Audio/foley_elements/spotting_notes.txt << 'NOTES'
===============================================================
FOLEY SPOTTING NOTES - "Winter Scene"
Supervising Sound Editor: J. Smith
Date: 2024-12-10
===============================================================

SCENE DETAILS:
  Character walks across a snowy field.
  Session sample rate: 44100 Hz

SOURCE AUDIO:
  File: raw_footsteps.wav

INSTRUCTIONS:
  1. Create a new audio track named "Synced Footsteps" (or rename Audio 1).
  2. Import the raw_footsteps.wav file onto this track.
  3. Extract four distinct transient events (footsteps) from the raw recording.
     Trim each footstep so it is no longer than 2.0 seconds.
  4. Align the START of each footstep to the exact timecodes below:
     - Cue 1: 00:00:05:00  (exactly 5.0 seconds)
     - Cue 2: 00:00:10:00  (exactly 10.0 seconds)
     - Cue 3: 00:00:15:00  (exactly 15.0 seconds)
     - Cue 4: 00:00:20:00  (exactly 20.0 seconds)
  5. Delete or mute all unused portions of the raw recording so ONLY the 
     4 synced footsteps remain active on the timeline.
  6. Save the session.
===============================================================
NOTES
chown ga:ga /home/ga/Audio/foley_elements/spotting_notes.txt

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing clean session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial state screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Spotting notes at /home/ga/Audio/foley_elements/spotting_notes.txt"