#!/bin/bash
echo "=== Setting up vinyl_ep_sequencing task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances to ensure a clean start
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Create backup of clean session on first run
if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
    echo "Created clean session backup"
fi

# Restore clean session (removes any previous user tracks/regions)
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
    echo "Restored clean session from backup"
fi

# Create directories for EP mixes
su - ga -c "mkdir -p /home/ga/Audio/ep_mixes"
rm -f /home/ga/Audio/ep_mixes/*.wav 2>/dev/null || true

# Source audio to slice (real classical music from the environment)
MASTER_AUDIO="/home/ga/Audio/samples/moonlight_sonata.wav"

# Fallback in case moonlight sonata is missing
if [ ! -f "$MASTER_AUDIO" ]; then
    MASTER_AUDIO=$(find /home/ga/Audio/samples/ -name "*.wav" | head -1)
fi

echo "Slicing EP tracks from $MASTER_AUDIO..."
# Create the 4 track assets with precise durations
# song1: 10 seconds
ffmpeg -y -hide_banner -loglevel error -i "$MASTER_AUDIO" -ss 0 -t 10 -ar 44100 -ac 2 "/home/ga/Audio/ep_mixes/song1_intro.wav"
# song2: 12 seconds
ffmpeg -y -hide_banner -loglevel error -i "$MASTER_AUDIO" -ss 10 -t 12 -ar 44100 -ac 2 "/home/ga/Audio/ep_mixes/song2_allegro.wav"
# song3: 15 seconds
ffmpeg -y -hide_banner -loglevel error -i "$MASTER_AUDIO" -ss 22 -t 15 -ar 44100 -ac 2 "/home/ga/Audio/ep_mixes/song3_adagio.wav"
# song4: 10 seconds
ffmpeg -y -hide_banner -loglevel error -i "$MASTER_AUDIO" -ss 37 -t 10 -ar 44100 -ac 2 "/home/ga/Audio/ep_mixes/song4_finale.wav"

chown -R ga:ga /home/ga/Audio/ep_mixes

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "EP Mixes ready in /home/ga/Audio/ep_mixes/"