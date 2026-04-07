#!/bin/bash
echo "=== Setting up dark_ride_audio_sync task ==="

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

# Create export directory
su - ga -c "mkdir -p /home/ga/Audio/ride_export"
rm -f /home/ga/Audio/ride_export/*.wav 2>/dev/null || true

# Verify sample files exist, set them up if missing
SAMPLES_DIR="/home/ga/Audio/samples"
su - ga -c "mkdir -p $SAMPLES_DIR"

if [ ! -f "$SAMPLES_DIR/moonlight_sonata.wav" ]; then
    echo "Downloading BGM sample..."
    wget -q --timeout=30 "https://archive.org/download/MoonlightSonata_755/Beethoven-MoonlightSonata.mp3" -O /tmp/bgm.mp3 2>/dev/null || true
    if [ -f /tmp/bgm.mp3 ]; then
        ffmpeg -y -i /tmp/bgm.mp3 -t 35 -ar 44100 -ac 2 "$SAMPLES_DIR/moonlight_sonata.wav" 2>/dev/null || true
    fi
fi

if [ ! -f "$SAMPLES_DIR/narration.wav" ]; then
    echo "Downloading narration sample..."
    wget -q --timeout=30 "https://archive.org/download/art_of_war_librivox/art_of_war_01_sun_tzu_64kb.mp3" -O /tmp/speech.mp3 2>/dev/null || true
    if [ -f /tmp/speech.mp3 ]; then
        ffmpeg -y -i /tmp/speech.mp3 -t 10 -ar 44100 -ac 1 "$SAMPLES_DIR/narration.wav" 2>/dev/null || true
    fi
fi
chown -R ga:ga "$SAMPLES_DIR"

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