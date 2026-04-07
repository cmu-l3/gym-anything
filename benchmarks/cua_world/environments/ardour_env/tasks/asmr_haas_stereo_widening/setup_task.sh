#!/bin/bash
echo "=== Setting up ASMR Haas Effect Stereo Widening Task ==="

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

# Create client files directory
su - ga -c "mkdir -p /home/ga/Audio/client_files"

# Locate a suitable mono narration file
SAMPLES_DIR="/home/ga/Audio/samples"
NARRATION_SRC=""

# Prefer speech sample
if [ -f "$SAMPLES_DIR/narration.wav" ]; then
    NARRATION_SRC="$SAMPLES_DIR/narration.wav"
elif [ -f "$SAMPLES_DIR/art_of_war.wav" ]; then
    NARRATION_SRC="$SAMPLES_DIR/art_of_war.wav"
else
    # Fallback to whatever is available
    NARRATION_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

if [ -n "$NARRATION_SRC" ]; then
    # Ensure it's mono for the sake of the task (using ffmpeg)
    ffmpeg -y -i "$NARRATION_SRC" -ac 1 /home/ga/Audio/client_files/narration.wav 2>/dev/null || \
        cp "$NARRATION_SRC" /home/ga/Audio/client_files/narration.wav
    chown ga:ga /home/ga/Audio/client_files/narration.wav
    echo "Provided client audio: /home/ga/Audio/client_files/narration.wav"
fi

# Create a brief document for context
cat > /home/ga/Audio/client_files/asmr_brief.txt << 'BRIEF'
================================================================
CLIENT BRIEF: Wellness App Audio
Task: ASMR Whisper Transformation (Haas Effect)
================================================================

We have a standard mono narration recording. We need it transformed 
into an immersive "ear-to-ear" ASMR whisper track.

INSTRUCTIONS FOR DAW (Ardour):
1. Create two separate audio tracks: "Left Whisper" and "Right Whisper".
2. Import 'narration.wav' onto both tracks.
3. Hard-pan the tracks: Left Whisper fully to the left, Right Whisper fully to the right.
4. Apply the Haas Effect: Nudge/shift the audio region on one of the tracks 
   so it starts slightly *after* the other (a micro-delay of about 5ms to 200ms).
   (Note: You may need to turn off grid snapping to make this micro-adjustment).
5. Gain Staging: The current recording is way too loud for ASMR. Drop the volume 
   (gain fader) on both tracks significantly, to between -24 dB and -12 dB.

Deliverable: Save the Ardour session when completed.
================================================================
BRIEF
chown ga:ga /home/ga/Audio/client_files/asmr_brief.txt

# Record baseline state (timestamps)
SESSION_FILE_PATH="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
if [ -f "$SESSION_FILE_PATH" ]; then
    INITIAL_MTIME=$(stat -c %Y "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    echo "$INITIAL_MTIME" > /tmp/initial_session_mtime
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="