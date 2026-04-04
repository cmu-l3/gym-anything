#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Audio Visualizer Task ==="

kill_vlc ga
sleep 1

USER_HOME="/home/ga"
AUDIO_DIR="$USER_HOME/Music/field_recordings"
OUTPUT_DIR="$USER_HOME/Pictures/audio_analysis"
INSTRUCTIONS_FILE="$USER_HOME/Desktop/AUDIO_ANALYSIS_TASK.txt"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /tmp/vlc_audio_viz_setup.log; }

# Create directories
log "Creating directories..."
mkdir -p "$AUDIO_DIR" "$OUTPUT_DIR"
chown -R ga:ga "$AUDIO_DIR" "$OUTPUT_DIR"

# Generate field recording audio with frequency variation
# Simulates bird calls with frequency sweeps at specific timestamps
log "Generating field recording audio (15 minutes with bird call at 3:00)..."

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    log "ERROR: ffmpeg not found, installing..."
    apt-get update && apt-get install -y ffmpeg
fi

# Create complex audio with:
# - Background ambient noise (brown noise)
# - Frequency sweep at 3:00 (180s) simulating bird call
# - Duration: 900 seconds (15 minutes) but we'll use first 5 minutes to save time
AUDIO_FILE="$AUDIO_DIR/morning_wetland_2024-03-15.mp3"

su - ga -c "ffmpeg -f lavfi -i 'anoisesrc=duration=300:color=brown:amplitude=0.05' \
    -f lavfi -i 'sine=frequency=1000:duration=300' \
    -f lavfi -i 'sine=frequency=5000:duration=2' \
    -filter_complex '[0:a]volume=0.3[bg]; \
                     [1:a]volume=0.1[ambient]; \
                     [2:a]adelay=180000|180000,volume=0.8[bird]; \
                     [bg][ambient]amix=inputs=2[base]; \
                     [base][bird]amix=inputs=2:dropout_transition=0[out]' \
    -map '[out]' -ac 2 -ar 44100 -b:a 192k \
    '$AUDIO_FILE' -y -loglevel error 2>&1" || {
    log "ERROR: Failed to generate audio with frequency variation"
    # Fallback: simple audio file
    su - ga -c "ffmpeg -f lavfi -i 'sine=frequency=440:duration=300' \
        -ac 2 -ar 44100 '$AUDIO_FILE' -y -loglevel error 2>&1"
}

if [ ! -f "$AUDIO_FILE" ]; then
    log "ERROR: Failed to create audio file"
    exit 1
fi

log "Audio file created: $AUDIO_FILE ($(du -h "$AUDIO_FILE" | cut -f1))"

# Create task instructions on Desktop
log "Creating task instructions..."
cat > "$INSTRUCTIONS_FILE" << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║           AUDIO VISUALIZATION TASK - Bird Call Analysis          ║
╚══════════════════════════════════════════════════════════════════╝

SCENARIO:
You recorded audio during a morning field session at a wetland.
Around the 3-minute mark (03:00), you heard what might be a rare
Yellow-bellied Warbler. To confirm, you need to VISUALLY analyze
the audio frequency pattern.

YOUR MISSION:
1. Open the audio file in VLC (may already be open):
   ~/Music/field_recordings/morning_wetland_2024-03-15.mp3

2. Enable VLC's AUDIO VISUALIZATION
   - You need to SEE the frequency spectrum or waveform
   - Hint: Check "View" menu → "Visualizations"
   - OR: "Audio" menu → "Visualizations"
   - Options: Spectrum, Spectrometer, Scope, or similar

3. Confirm visualization is ACTIVE and DISPLAYING
   - You should see moving bars, waveforms, or frequency graph
   - The visualization should update as audio plays

4. Navigate to approximately 03:00 (3 minutes)
   - Use timeline or seek controls
   - ±30 seconds is acceptable

5. Take a SCREENSHOT showing:
   - VLC window with visualization clearly visible
   - The frequency display or waveform
   - Timestamp showing around 03:00

SCREENSHOT LOCATION:
Save to: ~/Pictures/audio_analysis/warbler_analysis.png
(VLC default snapshot location also acceptable)

WHY THIS MATTERS:
Bird species have unique frequency "signatures" in their calls.
Warblers typically show sharp peaks at 4-6 kHz. Visual analysis
helps distinguish species that sound similar to untrained ears.

TROUBLESHOOTING:
- If no visualization appears, try different options under View menu
- Ensure audio is playing (visualization needs active audio)
- Spectrum analyzer is the most useful for frequency analysis

Good luck with your field research!
EOF

chown ga:ga "$INSTRUCTIONS_FILE"
log "Instructions created at: $INSTRUCTIONS_FILE"

# Reset VLC config to ensure no visualization is pre-enabled
log "Resetting VLC configuration..."
rm -rf "$USER_HOME/.config/vlc/vlcrc" 2>/dev/null || true
mkdir -p "$USER_HOME/.config/vlc"

# Create minimal VLC config with visualization disabled
cat > "$USER_HOME/.config/vlc/vlcrc" << 'EOF'
[qt]
qt-privacy-ask=0
qt-start-minimized=0
qt-notification=0

[core]
audio-visual=
vout=

[snapshot]
snapshot-path=/home/ga/Pictures/audio_analysis
snapshot-format=png
EOF

chown -R ga:ga "$USER_HOME/.config/vlc"

# Ensure VLC snapshot directory exists
mkdir -p "$USER_HOME/Pictures/vlc"
chown -R ga:ga "$USER_HOME/Pictures/vlc"

# Launch VLC with the audio file
log "Launching VLC with audio file..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc \
    --avcodec-hw=none \
    --no-video-title-show \
    --audio-visual=none \
    '$AUDIO_FILE' > /tmp/vlc_audio_viz_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    log "ERROR: VLC failed to start"
    cat /tmp/vlc_audio_viz_task.log 2>/dev/null || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    log "ERROR: VLC window did not appear"
    exit 1
fi

log "VLC started successfully"

# Click on center of the screen to select current desktop (should be done in all tasks)
log "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" 2>/dev/null || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    log "Focusing VLC window (WID: $wid)..."
    focus_window "$wid"
    sleep 1
else
    log "WARNING: Could not get VLC window ID"
fi

# Pause audio to give agent time to enable visualization
log "Pausing audio playback..."
su - ga -c "DISPLAY=:1 xdotool key space" 2>/dev/null || true
sleep 0.5

log "=== Audio Visualizer Task Setup Complete ==="
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Task: Enable Audio Visualization in VLC                   ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  Audio file: ~/Music/field_recordings/morning_wetland...   ║"
echo "║  Target: Enable visualization (spectrum/waveform)          ║"
echo "║  Navigate to: ~3:00 (3 minutes)                            ║"
echo "║  Action: Take screenshot showing visualization active      ║"
echo "║  Output: ~/Pictures/audio_analysis/warbler_analysis.png    ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  Instructions available on Desktop                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log "Agent should now: (1) Enable visualization, (2) Seek to 3:00, (3) Take screenshot"