#!/bin/bash
echo "=== Setting up field_recording_segmentation task ==="

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

# Create directories
su - ga -c "mkdir -p /home/ga/Audio/field_notes"

# Prepare 30-second audio
SAMPLES_DIR="/home/ga/Audio/samples"
SRC_AUDIO=""
for f in "$SAMPLES_DIR"/moonlight_sonata.wav "$SAMPLES_DIR"/art_of_war.wav "$SAMPLES_DIR"/good_morning.wav; do
    if [ -f "$f" ]; then
        SRC_AUDIO="$f"
        break
    fi
done

if [ -z "$SRC_AUDIO" ]; then
    SRC_AUDIO=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

if [ -n "$SRC_AUDIO" ]; then
    # Ensure it's exactly 30s
    ffmpeg -y -i "$SRC_AUDIO" -t 30 -ar 44100 -ac 1 /home/ga/Audio/field_notes/dawn_chorus_recording.wav 2>/dev/null || \
        cp "$SRC_AUDIO" /home/ga/Audio/field_notes/dawn_chorus_recording.wav
    chown ga:ga /home/ga/Audio/field_notes/dawn_chorus_recording.wav
fi

# Create field notes brief
cat > /home/ga/Audio/field_notes/dawn_chorus_brief.txt << 'BRIEF'
================================================================
YELLOWSTONE NATIONAL PARK - BIOACOUSTIC SURVEY
================================================================
Date: 2024-05-12
Location: Lamar Valley, Site 04
Recording ID: dawn_chorus_recording.wav (Duration: 30s)

INSTRUCTIONS FOR SPECIMEN PREPARATION:

1. Import the recording "dawn_chorus_recording.wav" onto the main track.
2. Split the continuous recording at the following timestamps to isolate species vocalizations:
   - 0:06.000 (6 seconds)
   - 0:12.000 (12 seconds)
   - 0:18.000 (18 seconds)
   - 0:24.000 (24 seconds)

3. Rename the 5 resulting regions sequentially:
   Region 1 (0:00-0:06): BKGD-ambient-01
   Region 2 (0:06-0:12): AMRO-vocalization
   Region 3 (0:12-0:18): MOCH-vocalization
   Region 4 (0:18-0:24): YWAR-vocalization
   Region 5 (0:24-0:30): BKGD-ambient-02

4. Create Range Markers for the three species vocalizations:
   - Range from 0:06 to 0:12 named "AMRO - American Robin"
   - Range from 0:12 to 0:18 named "MOCH - Mountain Chickadee"
   - Range from 0:18 to 0:24 named "YWAR - Yellow Warbler"

5. Mute the two background ambient regions (BKGD-ambient-01 and BKGD-ambient-02).
   Do not delete them; they must remain in the session but be muted.

6. Create a text file at /home/ga/Audio/field_notes/species_log.txt containing
   the three species codes (AMRO, MOCH, YWAR), their common names, and time windows.

AOU SPECIES CODES:
AMRO = American Robin
MOCH = Mountain Chickadee
YWAR = Yellow Warbler
BKGD = Background / Ambient
================================================================
BRIEF

chown ga:ga /home/ga/Audio/field_notes/dawn_chorus_brief.txt

# Initial states
date +%s > /tmp/task_start_timestamp
echo "0" > /tmp/initial_region_count

# Launch Ardour
launch_ardour_session "$SESSION_FILE"
sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup Complete ==="