#!/bin/bash
echo "=== Setting up un_style_voiceover_localization task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
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

# Restore clean session to ensure a fresh start state
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Create task directories
su - ga -c "mkdir -p /home/ga/Audio/localization"
su - ga -c "mkdir -p /home/ga/Audio/localized_export"
rm -f /home/ga/Audio/localized_export/*.wav 2>/dev/null || true
rm -f /home/ga/Audio/localization/*.wav 2>/dev/null || true

# Source audio (Use the pre-downloaded public domain files from ardour_env)
SAMPLES_DIR="/home/ga/Audio/samples"
RAW_DIR="/home/ga/Audio/localization"

# Find available speech samples
ORIGINAL_SRC=""
DUB_SRC=""

if [ -f "$SAMPLES_DIR/narration.wav" ]; then
    ORIGINAL_SRC="$SAMPLES_DIR/narration.wav"
fi

if [ -f "$SAMPLES_DIR/good_morning.wav" ]; then
    DUB_SRC="$SAMPLES_DIR/good_morning.wav"
fi

# Fallbacks if specific samples are missing
if [ -z "$ORIGINAL_SRC" ]; then ORIGINAL_SRC=$(find "$SAMPLES_DIR" -name "*.wav" | head -1); fi
if [ -z "$DUB_SRC" ]; then DUB_SRC=$(find "$SAMPLES_DIR" -name "*.wav" | tail -1); fi
if [ -z "$DUB_SRC" ]; then DUB_SRC="$ORIGINAL_SRC"; fi

# Trim and copy to target directory to serve as our realistic assets
ffmpeg -y -i "$ORIGINAL_SRC" -t 15 -ar 44100 -ac 1 "$RAW_DIR/interview_original.wav" 2>/dev/null || \
    cp "$ORIGINAL_SRC" "$RAW_DIR/interview_original.wav"

ffmpeg -y -i "$DUB_SRC" -t 12 -ar 44100 -ac 1 "$RAW_DIR/voiceover_dub.wav" 2>/dev/null || \
    cp "$DUB_SRC" "$RAW_DIR/voiceover_dub.wav"

# Create the Production Brief
cat > "$RAW_DIR/production_brief.txt" << 'BRIEF'
DOCUMENTARY AUDIO LOCALIZATION BRIEF
=================================================
Project: "Global Voices" Episode 4
Task: UN-Style Voiceover Mix
Editor: [Your Name]
Date: 2024-11-20

ASSETS PROVIDED:
  - interview_original.wav (Original foreign language audio)
  - voiceover_dub.wav      (Translated English dub)

INSTRUCTIONS:
1. TRACK SETUP:
   Create two audio tracks in Ardour. Name them exactly:
   - "Original Audio"
   - "Translated Dub"
   Import the respective WAV files onto these tracks.

2. TEMPORAL OFFSET (The UN-Style Timing):
   The original speaker must be heard alone for exactly 2.0 seconds 
   before the translator begins speaking.
   - Shift the "Translated Dub" region so it starts at 2.0 seconds 
     on the timeline.
   - The "Original Audio" should start at 0.0 seconds.

3. GAIN DUCKING:
   Once the translation starts, the original audio must sit quietly underneath.
   - Lower the fader/gain of the "Original Audio" track to -15 dB.
   - Keep the "Translated Dub" track at unity gain (0 dB).

4. SPATIAL SEPARATION (Panning):
   To help the listener's brain separate the overlapping voices:
   - Pan the "Original Audio" track partially to the LEFT (~20-30% left).
   - Pan the "Translated Dub" track partially to the RIGHT (~80-100% right).

5. EXPORT:
   Export the final stereo mix to:
   /home/ga/Audio/localized_export/un_style_mix.wav
=================================================
BRIEF

chown -R ga:ga /home/ga/Audio/localization
chown -R ga:ga /home/ga/Audio/localized_export

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"
sleep 3

# Take initial screenshot showing clean workspace
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Assets and brief available in /home/ga/Audio/localization/"