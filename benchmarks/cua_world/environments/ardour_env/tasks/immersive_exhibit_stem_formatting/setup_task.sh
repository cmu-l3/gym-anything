#!/bin/bash
echo "=== Setting up immersive_exhibit_stem_formatting task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
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

# Create task directories
RAW_DIR="/home/ga/Audio/exhibit_raw"
FINAL_DIR="/home/ga/Audio/exhibit_final"
su - ga -c "mkdir -p $RAW_DIR"
su - ga -c "mkdir -p $FINAL_DIR"
rm -f "$FINAL_DIR"/*.wav 2>/dev/null || true

# Find source audio sample
SAMPLES_DIR="/home/ga/Audio/samples"
SOURCE_AUDIO=""
for f in "$SAMPLES_DIR"/moonlight_sonata.wav "$SAMPLES_DIR"/good_morning.wav; do
    if [ -f "$f" ]; then
        SOURCE_AUDIO="$f"
        break
    fi
done

if [ -z "$SOURCE_AUDIO" ]; then
    SOURCE_AUDIO=$(find "$SAMPLES_DIR" -name "*.wav" -type f | head -1)
fi

echo "Using source audio: $SOURCE_AUDIO"

# Generate 3 distinct stems of ~25 seconds in length
# We want the agent to actively trim them down to exactly 20.0s.
echo "Generating exhibit stems..."

# Stem 1: Rumble (lowpass)
ffmpeg -y -i "$SOURCE_AUDIO" -af "lowpass=f=150" -t 25 -ar 44100 -ac 2 "$RAW_DIR/rumble.wav" 2>/dev/null || \
    cp "$SOURCE_AUDIO" "$RAW_DIR/rumble.wav"

# Stem 2: Ambience (reverb-like via highpass + delay if possible, else just copy)
ffmpeg -y -i "$SOURCE_AUDIO" -af "aecho=0.8:0.9:1000:0.3" -t 25 -ar 44100 -ac 2 "$RAW_DIR/ambience.wav" 2>/dev/null || \
    cp "$SOURCE_AUDIO" "$RAW_DIR/ambience.wav"

# Stem 3: FX (highpass)
ffmpeg -y -i "$SOURCE_AUDIO" -af "highpass=f=2000" -t 25 -ar 44100 -ac 2 "$RAW_DIR/fx.wav" 2>/dev/null || \
    cp "$SOURCE_AUDIO" "$RAW_DIR/fx.wav"

chown -R ga:ga "$RAW_DIR"
chown -R ga:ga "$FINAL_DIR"

# Create exhibit spec reference file
cat > "$RAW_DIR/exhibit_spec.txt" << 'SPEC'
================================================================
EXHIBIT AUDIO SPECIFICATION
Exhibit: "Deep Sea" Immersive Room
Role: AV Installation Technician
================================================================

HARDWARE LOOPER REQUIREMENTS:
To prevent phase drift over a 12-hour exhibition day, the 
playback hardware requires all audio stems to be EXACTLY the
same length and precisely aligned.

REQUIREMENTS:
1. Tracks:
   - "Tactile Bass"
   - "Overhead Ambience"
   - "Spot FX"

2. Media:
   - Import rumble.wav, ambience.wav, and fx.wav onto the respective tracks.

3. Timeline Formatting (CRITICAL):
   - All regions MUST start exactly at 0:00.000.
   - All regions MUST be trimmed at the end to be EXACTLY 20.000 seconds long.
     (Tip: Set grid to Seconds and enable Snap to Grid).

4. Navigational Marker:
   - Create a Range Marker from 0:00.000 to 20:00.000 named "Exhibit_Loop".

5. Mix Configuration:
   - Set "Tactile Bass" gain to +3 dB (to drive floor transducers).
   - Mute "Spot FX" (this layer is dynamically triggered by motion sensors).

6. Export:
   - Save session.
   - Export stereo mix to /home/ga/Audio/exhibit_final/exhibit_mix.wav
================================================================
SPEC

chown ga:ga "$RAW_DIR/exhibit_spec.txt"

# Record baseline state
if [ -f "$SESSION_FILE" ]; then
    INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
fi

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_FILE"

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Stems and specs located in $RAW_DIR"