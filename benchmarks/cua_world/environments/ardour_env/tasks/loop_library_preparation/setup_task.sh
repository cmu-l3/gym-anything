#!/bin/bash
echo "=== Setting up loop_library_preparation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Kill any existing Ardour instances
kill_ardour
sleep 2

# Create necessary directories
su - ga -c "mkdir -p /home/ga/Audio/loop_pack_delivery"
su - ga -c "mkdir -p /home/ga/Audio/marketplace_brief"

# Clean up any previous runs
rm -f /home/ga/Audio/loop_pack_delivery/*.wav 2>/dev/null || true
rm -f /home/ga/Audio/loop_pack_delivery/*.txt 2>/dev/null || true
rm -f /tmp/loop_task_result.json 2>/dev/null || true

# Ensure the source sample exists (install_ardour.sh downloads this, but we verify)
SAMPLE_FILE="/home/ga/Audio/samples/moonlight_sonata.wav"
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "WARNING: Primary sample not found, looking for fallback..."
    FALLBACK=$(find /home/ga/Audio/samples -name "*.wav" | head -1)
    if [ -n "$FALLBACK" ]; then
        cp "$FALLBACK" "$SAMPLE_FILE"
    else
        # Synthesize a fallback if totally missing (should not happen in real env)
        su - ga -c "sox -n -r 44100 -c 2 $SAMPLE_FILE synth 30 sine 440" 2>/dev/null || true
    fi
fi
chown ga:ga "$SAMPLE_FILE"

# Write the marketplace specification document
cat > /home/ga/Audio/marketplace_brief/submission_spec.txt << 'SPEC'
=== SAMPLE MARKETPLACE SUBMISSION SPECIFICATION ===
Pack Name: Moonlight Piano Loops
Category: Keys / Piano
Source File: /home/ga/Audio/samples/moonlight_sonata.wav

TECHNICAL REQUIREMENTS:
- Session tempo: 90 BPM (MUST change from default 120 BPM)
- Track name: "Piano Loops"
- Minimum loops: 3 (split the source audio into at least 3 separate regions)
- Range markers: Create at least 3 range markers with "Loop" in each name
  (e.g., "Loop 01 - Intro", "Loop 02 - Main", "Loop 03 - End")
- Track gain: -6 dB (marketplace standard headroom)
- Export: At least 2 loops as individual WAV files
- Export directory: /home/ga/Audio/loop_pack_delivery/

METADATA FILE (required):
Create a text file at /home/ga/Audio/loop_pack_delivery/pack_info.txt containing:
- Pack name: Moonlight Piano Loops
- BPM: 90
- Number of loops: (how many loops in your pack)
- Key: C# minor

All files must be WAV format, 44.1 kHz.
SPEC
chown ga:ga /home/ga/Audio/marketplace_brief/submission_spec.txt

# Create/Restore clean session
SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

if [ ! -f "$BACKUP_FILE" ] && [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
fi

# Launch Ardour with the session
launch_ardour_session "$SESSION_FILE"
sleep 4

# Take initial state screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="