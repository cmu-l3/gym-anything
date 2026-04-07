#!/bin/bash
# Setup for audio_region_editing task

echo "=== Setting up audio_region_editing task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

ARDOUR_BIN=$(get_ardour_bin)
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"

# Ensure clean state
kill_ardour
rm -rf /home/ga/Audio/bumper_export 2>/dev/null || true
mkdir -p /home/ga/Audio/bumper_export
chown -R ga:ga /home/ga/Audio/bumper_export

# Create the production brief
cat > /home/ga/Audio/bumper_brief.txt << 'BRIEF'
KPUB-FM Station Bumper — Production Brief
==========================================
Source: Narration recording on "Audio 1" track
Target duration: approximately 15 seconds

Instructions:
1. Rename the audio track from "Audio 1" to "Bumper"
2. Split the audio region at 5.0 seconds (sample position 220500 at 44100 Hz)
3. Split the audio region again at 20.0 seconds (sample position 882000)
4. Delete/remove the middle region (the section between 5.0s and 20.0s)
5. Move the remaining tail region (originally starting after 20.0s) so it
   begins immediately where the first region ends (at ~5.0 seconds / sample 220500)
6. Apply a fade-in of at least 0.1 seconds to the FIRST region
7. Apply a fade-out of at least 0.1 seconds to the LAST (repositioned tail) region
8. Place a location marker named "Edit Point" at the splice position (5.0 seconds)
9. Place a location marker named "Bumper End" at the end of the last region
10. Export the assembled bumper as a WAV file to:
    /home/ga/Audio/bumper_export/kpub_bumper.wav
11. Save the session (Ctrl+S)

Notes:
- Fades prevent audible clicks at edit boundaries
- Use Edit > Split Region (or press 'S') to split at the playhead position
BRIEF
chown ga:ga /home/ga/Audio/bumper_brief.txt

# Locate suitable narration sample
NARRATION_SRC=""
for f in /home/ga/Audio/samples/narration.wav /home/ga/Audio/samples/art_of_war.wav /home/ga/Audio/samples/good_morning.wav; do
    if [ -f "$f" ]; then
        NARRATION_SRC="$f"
        break
    fi
done

if [ -z "$NARRATION_SRC" ]; then
    echo "WARNING: No audio sample found. Generating speech-like audio..."
    su - ga -c "sox -n -r 44100 -c 1 /home/ga/Audio/samples/narration.wav synth 30 brownnoise vol 0.3 synth 30 sine mix 200 vol 0.1 2>/dev/null" || true
    NARRATION_SRC="/home/ga/Audio/samples/narration.wav"
fi

# Launch Ardour with the session
launch_ardour_session "$SESSION_FILE"
sleep 5

# Ensure narration audio is imported into the session
REGION_COUNT=$(grep -c '<Region ' "$SESSION_FILE" 2>/dev/null || echo "0")
if [ "$REGION_COUNT" -lt 1 ] && [ -f "$NARRATION_SRC" ]; then
    echo "Importing audio via Ardour UI..."
    DISPLAY=:1 xdotool key ctrl+i 2>/dev/null || true
    sleep 3
    IMPORT_WID=$(DISPLAY=:1 xdotool search --name "Import" 2>/dev/null | head -1)
    if [ -n "$IMPORT_WID" ]; then
        DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool type "$NARRATION_SRC" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 2
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5
    fi
fi

# Maximize and focus the main window
DISPLAY=:1 wmctrl -r "MyProject" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "MyProject" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record initial region count after import for anti-gaming verification
if [ -f "$SESSION_FILE" ]; then
    INITIAL_REGIONS=$(grep -c '<Region ' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_REGIONS" > /tmp/initial_region_count.txt
fi

echo "=== audio_region_editing task setup complete ==="