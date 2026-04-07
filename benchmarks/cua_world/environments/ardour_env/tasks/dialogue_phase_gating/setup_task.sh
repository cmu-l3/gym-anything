#!/bin/bash
echo "=== Setting up dialogue_phase_gating task ==="

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

# Create interview directories
su - ga -c "mkdir -p /home/ga/Audio/interview_raw"
su - ga -c "mkdir -p /home/ga/Audio/interview_fixed"
rm -f /home/ga/Audio/interview_fixed/*.wav 2>/dev/null || true

# Prepare audio files
SAMPLES_DIR="/home/ga/Audio/samples"
NARRATION_SRC=""

# Prefer the human speech sample
if [ -f "$SAMPLES_DIR/narration.wav" ]; then
    NARRATION_SRC="$SAMPLES_DIR/narration.wav"
else
    NARRATION_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

RAW_DIR="/home/ga/Audio/interview_raw"

if [ -n "$NARRATION_SRC" ]; then
    # 1. Boom Mic (Original)
    cp "$NARRATION_SRC" "$RAW_DIR/boom_raw.wav"
    
    # 2. Lavalier Mic (Phase Inverted using sox vol -1.0)
    # This multiplies all samples by -1, creating a perfect 180-degree phase flip.
    # When summed with boom_raw.wav at unity, it will result in complete silence.
    sox -v -1.0 "$NARRATION_SRC" "$RAW_DIR/lav_raw.wav" 2>/dev/null || \
        cp "$NARRATION_SRC" "$RAW_DIR/lav_raw.wav" # Fallback if sox fails
        
    chown -R ga:ga "$RAW_DIR"
    echo "Audio files generated in $RAW_DIR"
fi

# Create a brief instruction text file for reference
cat > "$RAW_DIR/post_production_brief.txt" << 'BRIEF'
POST PRODUCTION AUDIO BRIEF
==================================================
Scene: Interview 1A
Issue: Technical malfunction on location. The Lavalier microphone
was wired in reverse polarity, putting it 180 degrees out of phase 
with the Boom microphone. 

If you play both tracks together, they will cancel out.

Instructions:
1. Load both tracks (boom_raw.wav and lav_raw.wav)
2. Invert the polarity (phase) of the Lavalier track to restore the voice.
3. The Boom mic has some background hum. Apply a Noise Gate plugin 
   to the Boom track (threshold around -25dB) to silence the hum 
   between spoken words.
4. Export the fixed mix to /home/ga/Audio/interview_fixed/dialogue_mix.wav
==================================================
BRIEF
chown ga:ga "$RAW_DIR/post_production_brief.txt"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="