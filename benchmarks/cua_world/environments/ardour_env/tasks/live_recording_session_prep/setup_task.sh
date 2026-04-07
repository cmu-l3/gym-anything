#!/bin/bash
echo "=== Setting up live_recording_session_prep task ==="

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

# Create gig info directory
su - ga -c "mkdir -p /home/ga/Audio/gig_info"

# Create technical rider
cat > /home/ga/Audio/gig_info/tech_rider.txt << 'RIDER'
================================================================
MARCUS WEBB QUARTET - TECHNICAL RIDER
Live Recording Session
Venue: Blue Note Jazz Club
Date: December 14, 2024
Sound Engineer: [Your Name]
================================================================

ENSEMBLE:
  Marcus Webb - Tenor Saxophone
  Elena Vasquez - Piano
  James "JB" Brown - Upright Bass
  Kwame Asante - Drums

SESSION CONFIGURATION:
  Sample rate: 44100 Hz (venue standard)

INPUT TRACK LIST (create in this exact order):
  1. "Kick Drum"         - mono, pan: center
  2. "Drum Overheads"    - stereo, pan: center
  3. "Upright Bass DI"   - mono, pan: center
  4. "Piano Left"        - mono, pan: 35% left
  5. "Piano Right"       - mono, pan: 35% right
  6. "Tenor Sax"         - mono, pan: 15% right
  7. "Room Mics"         - stereo, pan: center

BUS TRACKS (create after input tracks):
  8. "Drum Sub"          - subgroup bus for Kick + Overheads
  9. "Piano Sub"         - subgroup bus for Piano L + Piano R

GAIN STAGING:
  - All input tracks (1-7): unity gain (0 dB)
  - Bus tracks (8-9): -6 dB
  - Master bus: 0 dB

SET LIST MARKERS (place these markers in the session):
  "Set 1 - Autumn Leaves"     at  0:00  (sample 0)
  "Blue in Green"              at  5:00  (sample 13230000)
  "All Blues"                  at 10:00  (sample 26460000)
  "Set Break"                  at 15:00  (sample 39690000)
  "Set 2 - My Favorite Things" at 20:00  (sample 52920000)
  "Giant Steps"                at 25:00  (sample 66150000)
  "Encore - Take Five"         at 30:00  (sample 79380000)

NOTES:
  - Piano Left and Piano Right simulate a stereo piano pair
  - Drum Sub should contain Kick and Overheads submixed
  - Room Mics capture the natural club ambience
  - All tracks should be record-armed and ready
  - Save the session when complete
================================================================
RIDER

chown ga:ga /home/ga/Audio/gig_info/tech_rider.txt

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
echo "Technical rider at /home/ga/Audio/gig_info/tech_rider.txt"
