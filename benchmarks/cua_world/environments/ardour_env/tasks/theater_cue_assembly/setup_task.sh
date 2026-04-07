#!/bin/bash
echo "=== Setting up theater_cue_assembly task ==="

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

# Create cue sheet
cat > /home/ga/Audio/cue_sheet.txt << 'CUESHEET'
===============================================================
DIRECTOR'S CUE SHEET
Play: "A Midnight Clear"
Sound Designer Prep
===============================================================

TIMELINE SPECIFICATIONS:

1. "Cue 1 Preshow" (Track)
   - Audio: /home/ga/Audio/samples/moonlight_sonata.wav
   - Start Time: 00:00:00
   - Note: Apply a 5-second fade-out to the end of this region.

2. "Cue 2 Prologue" (Track)
   - Audio: /home/ga/Audio/samples/narration.wav
   - Start Time: 00:02:00 (120 seconds)

3. "Cue 3 Intermission" (Track)
   - Audio: /home/ga/Audio/samples/moonlight_sonata.wav
   - Start Time: 00:05:00 (300 seconds)
   - Note: Reduce track gain to -10 dB (background music level).

WARNING MARKERS (Stage Management):
   - Add marker "House Lights Down" at 00:01:55
   - Add marker "Act 1 End" at 00:04:55

Please save the session once all cues and markers are placed.
===============================================================
CUESHEET
chown ga:ga /home/ga/Audio/cue_sheet.txt

# Record baseline state
SESSION_FILE_PATH="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
if [ -f "$SESSION_FILE_PATH" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="