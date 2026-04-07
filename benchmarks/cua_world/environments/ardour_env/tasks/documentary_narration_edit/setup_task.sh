#!/bin/bash
echo "=== Setting up Documentary Narration Edit task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Backup clean session
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi

if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
fi

# Create output directory
su - ga -c "mkdir -p /home/ga/Audio/documentary_export"
rm -f /home/ga/Audio/documentary_export/*.wav 2>/dev/null || true

# Verify/prepare narration audio file
NARRATION_FILE=""
for f in /home/ga/Audio/samples/narration.wav /home/ga/Audio/samples/art_of_war.wav /home/ga/Audio/samples/good_morning.wav /home/ga/Audio/samples/moonlight_sonata.wav; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        NARRATION_FILE="$f"
        break
    fi
done

# If no audio samples found, generate fallback with sox
if [ -z "$NARRATION_FILE" ]; then
    echo "WARNING: No audio samples found! Generating fallback with sox..."
    su - ga -c "mkdir -p /home/ga/Audio/samples"
    sox -n -r 44100 -c 1 /home/ga/Audio/samples/narration.wav synth 30 sine 440:880 fade h 0.5 30 0.5 2>/dev/null || true
    NARRATION_FILE="/home/ga/Audio/samples/narration.wav"
fi

# Ensure narration.wav is the canonical name
if [ "$NARRATION_FILE" != "/home/ga/Audio/samples/narration.wav" ]; then
    cp "$NARRATION_FILE" /home/ga/Audio/samples/narration.wav
fi
chown ga:ga /home/ga/Audio/samples/narration.wav

# Create production notes file
cat > /home/ga/Audio/production_notes.txt << 'PRODEOF'
==========================================================
  CLEARWATER DOCUMENTARY FILMS — POST-PRODUCTION NOTES
==========================================================

Project:     "Rivers of the Pacific Northwest"
Episode:     S01E03 — The Columbia Basin
Talent:      David Chen (narrator)
Session:     MyProject (Ardour)
Date:        2024-11-14

EDIT INSTRUCTIONS FOR NARRATION TRACK
--------------------------------------

Source file: /home/ga/Audio/samples/narration.wav

1. IMPORT the narration file onto an audio track in the session.

2. RENAME the track to: "Narration - David Chen"

3. SPLIT the recording at two points:
   - First cut at 10 seconds from the start of the region
   - Second cut at 20 seconds from the start of the region
   This creates three segments.

4. DELETE the MIDDLE segment (10s to 20s).
   Director's note: "David had a false start in this section.
   Remove it entirely."

5. FADES:
   - Apply a fade-in of at least 0.3 seconds to the first segment
   - Apply a fade-out of at least 0.3 seconds to the last segment
   (Use any fade shape — linear or curve is fine.)

6. MARKERS — Place at least two location markers:
   - "Intro" — at or near the beginning of the timeline
   - "Conclusion" — at or after the start of the final segment

7. EXPORT the result as a WAV file to:
      /home/ga/Audio/documentary_export/
   Filename should include "narration" (e.g., narration_clean.wav).

DELIVERY SPECS:
  Format:     WAV (any bit depth)
  Channels:   Stereo or Mono (either accepted)
  Sample rate: 44100 Hz

==========================================================
PRODEOF
chown ga:ga /home/ga/Audio/production_notes.txt

# Record initial session state for anti-gaming verification
if [ -f "$SESSION_FILE" ]; then
    INITIAL_REGIONS=$(grep -c '<Region ' "$SESSION_FILE" 2>/dev/null || echo "0")
    INITIAL_ROUTES=$(grep -c '<Route ' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_REGIONS" > /tmp/initial_region_count.txt
    echo "$INITIAL_ROUTES" > /tmp/initial_route_count.txt
else
    echo "0" > /tmp/initial_region_count.txt
    echo "0" > /tmp/initial_route_count.txt
fi

# Kill any running Ardour instance
if type kill_ardour &>/dev/null; then
    kill_ardour
else
    pkill -f "/usr/lib/ardour" 2>/dev/null || true
    sleep 2
    pkill -9 -f "/usr/lib/ardour" 2>/dev/null || true
fi
sleep 2

# Launch Ardour with the session
if type launch_ardour_session &>/dev/null; then
    launch_ardour_session "$SESSION_FILE"
else
    su - ga -c "DISPLAY=:1 setsid ardour8 '$SESSION_FILE' > /tmp/ardour_task.log 2>&1 &" || \
    su - ga -c "DISPLAY=:1 setsid ardour '$SESSION_FILE' > /tmp/ardour_task.log 2>&1 &"
    sleep 10
fi

# Take initial state screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_initial_state.png
else
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="
echo "Narration file: /home/ga/Audio/samples/narration.wav"
echo "Production notes: /home/ga/Audio/production_notes.txt"
echo "Export target: /home/ga/Audio/documentary_export/"