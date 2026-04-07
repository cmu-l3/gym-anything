#!/bin/bash
echo "=== Setting up Broadcast Profanity Censor Edit Task ==="

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

# Create working directories
su - ga -c "mkdir -p /home/ga/Audio/assets"
su - ga -c "mkdir -p /home/ga/Audio/export"
rm -f /home/ga/Audio/export/*.wav 2>/dev/null || true

# Prepare audio assets
SAMPLES_DIR="/home/ga/Audio/samples"
ASSETS_DIR="/home/ga/Audio/assets"

# 1. Provide the interview file
# Using the pre-installed speech/narration sample if available, else fallback
INTERVIEW_SRC=""
for f in "$SAMPLES_DIR"/narration.wav "$SAMPLES_DIR"/art_of_war.wav "$SAMPLES_DIR"/good_morning.wav; do
    if [ -f "$f" ]; then
        INTERVIEW_SRC="$f"
        break
    fi
done

if [ -z "$INTERVIEW_SRC" ]; then
    # Fallback to any wav
    INTERVIEW_SRC=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

if [ -n "$INTERVIEW_SRC" ]; then
    # Ensure it's at least 20 seconds long, padded with silence if necessary
    ffmpeg -y -i "$INTERVIEW_SRC" -af "apad=pad_dur=20" -t 30 -ar 44100 -ac 1 "$ASSETS_DIR/interview_raw.wav" 2>/dev/null || \
        cp "$INTERVIEW_SRC" "$ASSETS_DIR/interview_raw.wav"
fi

# 2. Generate a 10-second 1kHz continuous censor beep using ffmpeg
ffmpeg -y -f lavfi -i "sine=frequency=1000:duration=10" -ar 44100 -ac 1 "$ASSETS_DIR/censor_beep_1khz.wav" 2>/dev/null

# Fix ownership
chown -R ga:ga /home/ga/Audio/assets
chown -R ga:ga /home/ga/Audio/export

# Create a brief instruction text file for reference
cat > /home/ga/Audio/assets/compliance_brief.txt << 'BRIEF'
FCC COMPLIANCE EDITING BRIEF
=========================================
Target: Syndicated Daytime Interview
Format: 44.1 kHz, 16-bit WAV

INSTRUCTIONS:
1. Import "interview_raw.wav" to a new track named "Interview".
2. Import "censor_beep_1khz.wav" to a new track named "Censor".
3. An expletive occurs precisely between 14.5s and 15.5s in the interview.
   - You MUST use region splitting to cut the Interview region at exactly 14.5s and 15.5s.
   - Delete or mute the offending 1-second segment from the Interview track.
4. Move and trim the beep region on the Censor track so it perfectly covers 
   that exact 1-second gap (from 14.5s to 15.5s).
5. Export the session as a stereo WAV file to:
   /home/ga/Audio/export/fcc_compliant_mix.wav

Do not alter the timing of the rest of the interview.
BRIEF
chown ga:ga /home/ga/Audio/assets/compliance_brief.txt

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
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
echo "Assets and brief ready in /home/ga/Audio/assets/"