#!/bin/bash
echo "=== Setting up Historical Audio Phase Restoration Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any existing Ardour instances and restore clean session
kill_ardour
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
fi

# Create required directories
su - ga -c "mkdir -p /home/ga/Audio/archives"
su - ga -c "mkdir -p /home/ga/Audio/restored_export"
rm -f /home/ga/Audio/restored_export/*.wav 2>/dev/null || true

# Generate realistic audio test files using ffmpeg and sox
echo "Generating synthetic hum and mixing with speech..."
SAMPLES_DIR="/home/ga/Audio/samples"

# Prefer the human speech sample if available
SPEECH_SRC="$SAMPLES_DIR/narration.wav"
if [ ! -f "$SPEECH_SRC" ]; then
    SPEECH_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

# 1. Extract 15 seconds of speech, convert to mono 44.1kHz
ffmpeg -y -i "$SPEECH_SRC" -t 15 -ac 1 -ar 44100 /tmp/speech_base.wav 2>/dev/null

# 2. Generate 15 seconds of a 60Hz electrical hum
ffmpeg -y -f lavfi -i "sine=frequency=60:duration=15" -ac 1 -ar 44100 /tmp/hum_base.wav 2>/dev/null

# 3. Mix speech and hum (the corrupted interview tape)
sox -v 0.7 /tmp/speech_base.wav -v 0.3 /tmp/hum_base.wav /home/ga/Audio/archives/interview_tape.wav

# 4. Save the isolated hum profile (must perfectly match the hum in the interview)
sox -v 0.3 /tmp/hum_base.wav /home/ga/Audio/archives/hum_isolated.wav

chown -R ga:ga /home/ga/Audio/archives

# Record initial session tracks and markers for verification baseline
if [ -f "$SESSION_FILE" ]; then
    grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null > /tmp/initial_track_count
    grep -c '<Location.*IsMark' "$SESSION_FILE" 2>/dev/null > /tmp/initial_marker_count
else
    echo "0" > /tmp/initial_track_count
    echo "0" > /tmp/initial_marker_count
fi

# Launch Ardour
echo "Launching Ardour..."
launch_ardour_session "$SESSION_FILE"

# Wait for UI to stabilize and take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="