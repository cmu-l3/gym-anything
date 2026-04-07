#!/bin/bash
echo "=== Setting up theatrical_soundscape_design task ==="

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

# Verify samples exist, otherwise copy fallback
mkdir -p /home/ga/Audio/samples
if [ ! -f "/home/ga/Audio/samples/good_morning.wav" ]; then
    if [ -f "/home/ga/Audio/samples/narration.wav" ]; then
        cp "/home/ga/Audio/samples/narration.wav" "/home/ga/Audio/samples/good_morning.wav"
        echo "Created fallback for good_morning.wav"
    fi
fi
chown -R ga:ga /home/ga/Audio/samples

# Create a cue sheet on the desktop for the agent's reference
cat > /home/ga/Desktop/Cue_Sheet.txt << 'EOF'
THEATRICAL SOUND DESIGN - OPENING SCENE
=======================================
Tracks to Create:
1. Piano_Atmos
2. Left_Monologue
3. Right_Interruption

Media to Import (from ~/Audio/samples/):
- moonlight_sonata.wav -> Piano_Atmos (Start at 0.0s)
- narration.wav -> Left_Monologue (Start at 2.0s)
- good_morning.wav -> Right_Interruption (Start at 5.0s)

Spatial Mix (Pan):
- Left_Monologue: 100% Left
- Right_Interruption: 100% Right
- Piano_Atmos: Center

Depth Mix (Gain):
- Piano_Atmos: -12 dB
- Left_Monologue: -6 dB
- Right_Interruption: 0 dB

Fades & Markers:
- Add a >= 2.0s fade-in to the Piano_Atmos region.
- Add markers: "Scene Start" (0.0s), "Monologue" (2.0s), "Interruption" (5.0s).

Don't forget to save (Ctrl+S)!
EOF
chown ga:ga /home/ga/Desktop/Cue_Sheet.txt

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