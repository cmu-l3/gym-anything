#!/bin/bash
# Do NOT use set -e — xdotool/wmctrl may return non-zero harmlessly

echo "=== Setting up Audiobook Chapter Export task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"

# Kill any running Ardour instance
pkill -f "/usr/lib/ardour" 2>/dev/null || true
sleep 2
pkill -9 -f "/usr/lib/ardour" 2>/dev/null || true

# Restore clean session if we have a backup, or backup the current one
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
fi

# Create the audiobook project directory with production brief
echo "=== Creating production brief ==="
su - ga -c "mkdir -p /home/ga/Audio/audiobook_project"

# Copy narration audio as the chapter file
NARRATION_SRC=""
for f in /home/ga/Audio/samples/narration.wav /home/ga/Audio/samples/good_morning.wav /home/ga/Audio/samples/moonlight_sonata.wav; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        NARRATION_SRC="$f"
        break
    fi
done

if [ -n "$NARRATION_SRC" ]; then
    cp "$NARRATION_SRC" /home/ga/Audio/audiobook_project/narration_chapter.wav
    echo "Copied $NARRATION_SRC as narration_chapter.wav"
else
    # Generate a 30-second audio file with sox as fallback if missing
    sox -n -r 44100 -c 1 /home/ga/Audio/audiobook_project/narration_chapter.wav \
        synth 30 sine 300:200 gain -20 2>/dev/null || true
    echo "Generated fallback narration_chapter.wav"
fi

# Create the production brief
cat > /home/ga/Audio/audiobook_project/production_brief.txt << 'BRIEF'
==============================================================
  BLACKTHORN PUBLISHING — AUDIOBOOK PRODUCTION BRIEF
==============================================================

Title:        "The Last Meridian" by Eleanor Voss
Chapter:      05 — The Awakening
Narrator:     (assigned)
Session Rate: 44100 Hz / 16-bit

--------------------------------------------------------------
TRACK NAMING CONVENTION
--------------------------------------------------------------
Rename the audio track to exactly:

    Ch05 - The Awakening

--------------------------------------------------------------
SECTION MARKERS (Point Markers)
--------------------------------------------------------------
Place point markers at the following timecodes within the
chapter recording. These are used by our QA reviewers to
navigate during quality checks.

  Marker Name          Timecode
  -------------------  --------
  Room Tone            0:00
  Narration Begin      0:02
  Paragraph 2          0:10
  Paragraph 3          0:18
  Narration End        0:28

--------------------------------------------------------------
RETAIL SAMPLE RANGE
--------------------------------------------------------------
Create a RANGE marker (not a point marker) for the retail
sample clip. This excerpt will appear on the Audible
storefront as the book preview.

  Range Name:   Retail Sample
  Start:        0:05
  End:          0:20

--------------------------------------------------------------
EXPORT DELIVERABLES
--------------------------------------------------------------
Export the following files to:

    /home/ga/Audio/audiobook_delivery/

Create this directory if it does not exist.

1. Full chapter mix — WAV format
   Filename must contain the word "chapter"
   (e.g., chapter_05.wav)

2. Retail sample clip — WAV format, the "Retail Sample"
   range only
   Filename must contain "retail" or "sample"
   (e.g., retail_sample.wav)

--------------------------------------------------------------
NOTES
--------------------------------------------------------------
- Do NOT delete or destructively edit the original audio.
- All markers should be placed on the main timeline.
- The range marker must span a region (start ≠ end).

==============================================================
BRIEF

chown -R ga:ga /home/ga/Audio/audiobook_project

# Ensure delivery directory does NOT exist yet (agent must create it)
rm -rf /home/ga/Audio/audiobook_delivery
su - ga -c "mkdir -p /home/ga/Audio/audiobook_delivery"

# Clean any previous export artifacts
rm -rf "$SESSION_DIR/export/"* 2>/dev/null || true

echo "=== Launching Ardour with session ==="
if type launch_ardour_session &>/dev/null; then
    launch_ardour_session "$SESSION_FILE"
else
    # Fallback launch
    su - ga -c "DISPLAY=:1 setsid ardour8 '$SESSION_FILE' > /tmp/ardour_task.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 setsid ardour '$SESSION_FILE' > /tmp/ardour_task.log 2>&1 &"
    sleep 15
    DISPLAY=:1 wmctrl -r "MyProject" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for session to stabilize
sleep 5

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Audiobook Chapter Export task setup complete ==="