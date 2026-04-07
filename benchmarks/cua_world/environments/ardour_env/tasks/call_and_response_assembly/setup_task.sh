#!/bin/bash
echo "=== Setting up call_and_response_assembly task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

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

# Create edtech raw and export directories
su - ga -c "mkdir -p /home/ga/Audio/edtech_raw"
su - ga -c "mkdir -p /home/ga/Audio/edtech_export"
rm -f /home/ga/Audio/edtech_export/*.wav 2>/dev/null || true
rm -f /home/ga/Audio/edtech_raw/*.wav 2>/dev/null || true

# Find available samples from the Ardour environment installation
SAMPLES_DIR="/home/ga/Audio/samples"
RAW_DIR="/home/ga/Audio/edtech_raw"

# We need a speech sample and a music sample
MUSIC_FILE="$SAMPLES_DIR/moonlight_sonata.wav"
SPEECH_FILE="$SAMPLES_DIR/narration.wav"

# Fallbacks if specific files are missing
if [ ! -f "$MUSIC_FILE" ]; then
    MUSIC_FILE=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi
if [ ! -f "$SPEECH_FILE" ]; then
    SPEECH_FILE=$(find "$SAMPLES_DIR" -name "*.wav" -type f | tail -1)
fi

# Trim the narration to exactly 15 seconds to ensure standard phrase lengths
ffmpeg -y -i "$SPEECH_FILE" -t 15 -ar 44100 -ac 1 "$RAW_DIR/narration.wav" 2>/dev/null || \
    cp "$SPEECH_FILE" "$RAW_DIR/narration.wav"

# Trim the music to exactly 30 seconds for the bed
ffmpeg -y -i "$MUSIC_FILE" -t 30 -ar 44100 -ac 2 "$RAW_DIR/moonlight_sonata.wav" 2>/dev/null || \
    cp "$MUSIC_FILE" "$RAW_DIR/moonlight_sonata.wav"

# Create production brief
cat > "$RAW_DIR/production_brief.txt" << 'BRIEF'
LANGUAGE LEARNING MODULE - "Listen and Repeat"
=======================================================
Instructional Designer: Alex Rivera
Format: Shadowing Exercise
Sample Rate: 44100 Hz

FILES PROVIDED:
  - narration.wav (15-second continuous teacher speech)
  - moonlight_sonata.wav (30-second background music)

TRACK SETUP:
  1. Create an audio track named "Voice" and import narration.wav onto it.
  2. Create an audio track named "MusicBed" and import moonlight_sonata.wav onto it.

EDITING INSTRUCTIONS (VOICE TRACK):
  The narration is currently a continuous 15-second clip. 
  You must split it into three 5-second phrases and insert 5-second gaps for the student to repeat the phrase.
  
  - Phrase 1: 0.0s to 5.0s (Leave at the beginning)
  - Phrase 2: 5.0s to 10.0s (Move so it starts at exactly 10.0s, creating a 5s gap)
  - Phrase 3: 10.0s to 15.0s (Move so it starts at exactly 20.0s, creating another 5s gap)

  *Hint: Split the Voice region at 5.0s and 10.0s, then drag the separated regions to the right.*

PEDAGOGICAL MARKERS:
  Place session location markers at the beginning of each student repetition gap:
  - Marker "Repeat 1" at 5.0 seconds
  - Marker "Repeat 2" at 15.0 seconds

MIXING INSTRUCTIONS (MUSICBED TRACK):
  Do not cut the music. Let it play continuously for the full 25-30 seconds.
  Lower the volume of the "MusicBed" track to approximately -15 dB so it sits quietly behind the teacher's voice.

DELIVERY:
  Export the entire session as a WAV file to:
  /home/ga/Audio/edtech_export/listen_and_repeat.wav
BRIEF

chown -R ga:ga "$RAW_DIR" /home/ga/Audio/edtech_export

# Record baseline counts for anti-gaming verification
SESSION_FILE_PATH="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
if [ -f "$SESSION_FILE_PATH" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="
echo "Raw audio and production brief in /home/ga/Audio/edtech_raw/"