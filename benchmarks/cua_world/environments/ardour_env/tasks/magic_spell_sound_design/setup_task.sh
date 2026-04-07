#!/bin/bash
echo "=== Setting up magic_spell_sound_design task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Kill any existing Ardour instances
kill_ardour
sleep 2

# Restore clean session from backup
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
fi

# Ensure directories exist
su - ga -c "mkdir -p /home/ga/Audio/samples"
su - ga -c "mkdir -p /home/ga/Audio/export"
rm -f /home/ga/Audio/export/time_spell.wav 2>/dev/null || true

# Generate the raw material for the task (Real acoustic data from classical piece)
# We extract the first 3 seconds of the Moonlight Sonata (a strong piano chord strike and decay)
SOURCE_AUDIO="/home/ga/Audio/samples/moonlight_sonata.wav"
TARGET_AUDIO="/home/ga/Audio/samples/magic_strike.wav"

echo "Creating magic_strike.wav from real acoustic recording..."
if [ -f "$SOURCE_AUDIO" ]; then
    ffmpeg -y -i "$SOURCE_AUDIO" -t 3 -ar 44100 -ac 2 "$TARGET_AUDIO" 2>/dev/null
else
    # Fallback if the specific sample is missing: generate a real-sounding bell/strike using sox
    sox -n "$TARGET_AUDIO" synth 3 pluck %-10 vol 0.8 2>/dev/null
fi
chown ga:ga "$TARGET_AUDIO"

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Launch Ardour with the existing session
echo "Launching Ardour..."
launch_ardour_session "$SESSION_FILE"
sleep 4

# Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured successfully."
else
    echo "WARNING: Could not capture initial screenshot."
fi

echo "=== Task setup complete ==="