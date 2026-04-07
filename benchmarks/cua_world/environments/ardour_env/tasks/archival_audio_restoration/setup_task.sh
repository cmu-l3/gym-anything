#!/bin/bash
echo "=== Setting up archival_audio_restoration task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Kill any existing Ardour instances
kill_ardour
sleep 2

# Reset Ardour session to a clean state
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
fi

# Prepare environment and expected directories
su - ga -c "mkdir -p /home/ga/Audio/archive_master"
rm -f /home/ga/Audio/archive_master/*.flac 2>/dev/null || true

# Generate realistic raw data: 4 seconds of "tape leader noise" (pink noise) + speech recording
RAW_FILE="/home/ga/Audio/samples/oral_history_raw.wav"
LEADER_FILE="/tmp/tape_leader.wav"

echo "Generating raw oral history asset..."
# Create 4 seconds of low-volume pink noise
ffmpeg -y -f lavfi -i "anoisesrc=color=pink:r=44100:d=4.0,volume=0.01" "$LEADER_FILE" 2>/dev/null

# Concatenate leader and existing speech sample
SPEECH_SAMPLE="/home/ga/Audio/samples/narration.wav"

if [ -f "$SPEECH_SAMPLE" ]; then
    ffmpeg -y -i "$LEADER_FILE" -i "$SPEECH_SAMPLE" -filter_complex "[0:0][1:0]concat=n=2:v=0:a=1[out]" -map "[out]" "$RAW_FILE" 2>/dev/null
else
    # Fallback to just the noise if speech is missing
    cp "$LEADER_FILE" "$RAW_FILE"
fi

chown ga:ga "$RAW_FILE"

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"
sleep 4

# Maximize and take initial state screenshot
WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="