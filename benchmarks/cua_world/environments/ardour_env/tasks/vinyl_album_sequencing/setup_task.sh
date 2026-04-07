#!/bin/bash
echo "=== Setting up vinyl_album_sequencing task ==="

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

# Create task directories
su - ga -c "mkdir -p /home/ga/Audio/vinyl_source"
su - ga -c "mkdir -p /home/ga/Audio/vinyl_delivery"
rm -f /home/ga/Audio/vinyl_delivery/*.wav 2>/dev/null || true

# Provide source audio files
SAMPLES_DIR="/home/ga/Audio/samples"
if [ -f "$SAMPLES_DIR/moonlight_sonata.wav" ]; then
    cp "$SAMPLES_DIR/moonlight_sonata.wav" /home/ga/Audio/vinyl_source/
fi
if [ -f "$SAMPLES_DIR/narration.wav" ]; then
    cp "$SAMPLES_DIR/narration.wav" /home/ga/Audio/vinyl_source/
fi

chown -R ga:ga /home/ga/Audio/vinyl_source

# Create pressing plant specifications document
cat > /home/ga/Audio/vinyl_source/pressing_plant_spec.txt << 'SPEC'
================================================================
VINYL PRE-MASTERING SPECIFICATION
Format: 7-inch Split Single (33 1/3 RPM)
Side: A
================================================================

DELIVERABLES:
The pressing plant requires Side A to be delivered as a SINGLE 
continuous WAV file (44.1 kHz, 16-bit stereo) exported to:
/home/ga/Audio/vinyl_delivery/master.wav

SOURCE MATERIAL:
1. Track A1: moonlight_sonata.wav
2. Track A2: narration.wav

SEQUENCING INSTRUCTIONS:
1. Create a single audio track named: "Vinyl Pre-Master"
2. Import Track A1 (moonlight_sonata.wav) so it starts exactly 
   at the beginning of the timeline (00:00:00:00).
3. Import Track A2 (narration.wav) on the SAME track, placing it 
   so there is EXACTLY 3.0 seconds of silence between the end 
   of A1 and the start of A2.
4. Apply a 2.0-second fade-out to the very end of Track A2.

INDEXING / MARKERS:
The lathe engineer requires markers to locate track starts.
- Create a location marker named "Side A1" exactly where Track A1 begins.
- Create a location marker named "Side A2" exactly where Track A2 begins.

================================================================
CRITICAL: The 3.0-second gap must be mathematically precise based 
on the end sample of the first region.
================================================================
SPEC

chown ga:ga /home/ga/Audio/vinyl_source/pressing_plant_spec.txt

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Record task start timestamp for anti-gaming (checking export file age)
date +%s > /tmp/task_start_timestamp

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Specifications at /home/ga/Audio/vinyl_source/pressing_plant_spec.txt"