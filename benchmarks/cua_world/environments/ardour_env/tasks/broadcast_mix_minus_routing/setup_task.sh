#!/bin/bash
echo "=== Setting up broadcast_mix_minus_routing task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

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

# Make sure sample files exist (fallback if env setup missed them)
mkdir -p /home/ga/Audio/samples
if [ ! -f /home/ga/Audio/samples/narration.wav ]; then
    touch /home/ga/Audio/samples/narration.wav # Mock if missing
fi
if [ ! -f /home/ga/Audio/samples/good_morning.wav ]; then
    touch /home/ga/Audio/samples/good_morning.wav # Mock if missing
fi

# Create production brief
cat > /home/ga/Audio/mix_minus_brief.txt << 'BRIEF'
BROADCAST MIX-MINUS ROUTING SPECIFICATION
================================================================
Podcast: "Live Tech Talk"
Date: Today

We have a live show today with an in-studio host and a remote 
guest calling in via Zoom.

We need a dedicated "Mix Minus" bus to send audio back to the 
Zoom call. If we send the main Master mix, the remote guest 
will hear a delayed echo of their own voice, which makes it 
impossible to talk.

TRACKS TO CREATE:
1. "Host Mic" (Audio Track) -> Import narration.wav here
2. "Soundboard" (Audio Track) -> Leave empty
3. "Remote Guest" (Audio Track) -> Import good_morning.wav here
4. "Mix Minus" (Audio Bus)

ROUTING REQUIREMENTS:
- "Host Mic" audio must go to the Master AND the "Mix Minus" bus.
- "Soundboard" audio must go to the Master AND the "Mix Minus" bus.
- "Remote Guest" audio must go to the Master ONLY. 
  *** DO NOT route "Remote Guest" to the "Mix Minus" bus! ***

LEVEL SETTINGS:
- The remote guest is quiet. Set "Remote Guest" fader to +6 dB.
- To prevent clipping the Zoom input, set "Mix Minus" bus fader to -3 dB.

SAVE THE SESSION (Ctrl+S) WHEN FINISHED!
================================================================
BRIEF

chown ga:ga /home/ga/Audio/mix_minus_brief.txt

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot showing Ardour is open
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="