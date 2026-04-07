#!/bin/bash
echo "=== Setting up podcast_production_mix task ==="

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

# Create podcast raw audio directory
su - ga -c "mkdir -p /home/ga/Audio/podcast_raw"
su - ga -c "mkdir -p /home/ga/Audio/podcast_final"
rm -f /home/ga/Audio/podcast_final/*.wav 2>/dev/null || true

# Copy audio samples as podcast segments
# Use available samples from the install step
SAMPLES_DIR="/home/ga/Audio/samples"
RAW_DIR="/home/ga/Audio/podcast_raw"

# Find available samples
MUSIC_FILE=""
SPEECH_FILE=""
for f in "$SAMPLES_DIR"/moonlight_sonata.wav "$SAMPLES_DIR"/good_morning.wav; do
    if [ -f "$f" ]; then
        if [ -z "$MUSIC_FILE" ]; then
            MUSIC_FILE="$f"
        elif [ -z "$SPEECH_FILE" ]; then
            SPEECH_FILE="$f"
        fi
    fi
done

# Fallback: use any available WAV
if [ -z "$MUSIC_FILE" ]; then
    MUSIC_FILE=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi
if [ -z "$SPEECH_FILE" ]; then
    SPEECH_FILE=$(find "$SAMPLES_DIR" -name "*.wav" -type f | tail -1)
fi

# If we only have one file, use it for all segments
if [ -z "$SPEECH_FILE" ]; then
    SPEECH_FILE="$MUSIC_FILE"
fi

# Create podcast segments using ffmpeg
# Intro: first 8 seconds of music
ffmpeg -y -i "$MUSIC_FILE" -t 8 -ar 44100 -ac 2 "$RAW_DIR/intro_theme.wav" 2>/dev/null || \
    cp "$MUSIC_FILE" "$RAW_DIR/intro_theme.wav"

# Interview: use speech sample (or different segment of music)
if [ "$SPEECH_FILE" != "$MUSIC_FILE" ]; then
    ffmpeg -y -i "$SPEECH_FILE" -t 20 -ar 44100 -ac 2 "$RAW_DIR/interview_segment.wav" 2>/dev/null || \
        cp "$SPEECH_FILE" "$RAW_DIR/interview_segment.wav"
else
    ffmpeg -y -i "$MUSIC_FILE" -ss 5 -t 20 -ar 44100 -ac 2 "$RAW_DIR/interview_segment.wav" 2>/dev/null || \
        cp "$MUSIC_FILE" "$RAW_DIR/interview_segment.wav"
fi

# Outro: last 8 seconds of music (or copy intro)
ffmpeg -y -i "$MUSIC_FILE" -ss 15 -t 8 -ar 44100 -ac 2 "$RAW_DIR/outro_theme.wav" 2>/dev/null || \
    cp "$RAW_DIR/intro_theme.wav" "$RAW_DIR/outro_theme.wav"

chown -R ga:ga "$RAW_DIR" /home/ga/Audio/podcast_final

# Create production brief
cat > "$RAW_DIR/production_brief.txt" << 'BRIEF'
COMMUNITY VOICES PODCAST - Episode 47 Production Brief
=======================================================
Producer: Sarah Chen, WKRP Community Radio
Date: 2024-12-09

AUDIO FILES PROVIDED:
  - intro_theme.wav    (station intro music)
  - interview_segment.wav  (recorded interview with guest)
  - outro_theme.wav    (closing music)

TRACK LAYOUT (create one track per audio file):
  Track 1: "Intro Theme"       - intro music
  Track 2: "Interview"         - main interview content
  Track 3: "Outro Theme"       - closing music

ARRANGEMENT:
  - Intro plays first, starting at position 0:00
  - Interview starts after intro ends (approximately 0:08 - 0:10)
  - Outro starts after interview ends

LEVEL REQUIREMENTS:
  - Music tracks (Intro Theme, Outro Theme): -12 dB
  - Speech track (Interview): 0 dB (unity gain)

MARKERS (add these session markers):
  - "Episode Start" at 0:00
  - "Interview Begin" where interview starts
  - "Outro Begin" where outro starts
  - "Episode End" at the end

DELIVERY:
  Export the final mix as stereo WAV (44.1 kHz, 16-bit)
  to /home/ga/Audio/podcast_final/
BRIEF

chown ga:ga "$RAW_DIR/production_brief.txt"

# Record baseline state
SESSION_FILE_PATH="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
if [ -f "$SESSION_FILE_PATH" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    INITIAL_MARKER_COUNT=$(grep -c '<Location.*IsMark' "$SESSION_FILE_PATH" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
    echo "$INITIAL_MARKER_COUNT" > /tmp/initial_marker_count
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Raw audio and production brief in /home/ga/Audio/podcast_raw/"
