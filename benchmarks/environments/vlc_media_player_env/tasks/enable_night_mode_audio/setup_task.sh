#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Enable Night Mode Audio Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Setup directories
USER_HOME="/home/ga"
VIDEOS_DIR="$USER_HOME/Videos"
CONFIG_DIR="$USER_HOME/.config/vlc"
DESKTOP_DIR="$USER_HOME/Desktop"

mkdir -p "$VIDEOS_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$DESKTOP_DIR"

# Generate test video with extreme dynamic range audio
# This creates a 30-second video with alternating quiet and loud audio
echo "[INFO] Generating test video with extreme dynamic range..."

AUDIO_FILE="/tmp/dynamic_audio.wav"
VIDEO_FILE="$VIDEOS_DIR/action_movie.mp4"

# Create audio with quiet parts (-25dB) and loud parts (0dB) alternating every 5 seconds
# This simulates dialogue (quiet) and action scenes (loud)
ffmpeg -f lavfi -i "sine=frequency=440:duration=5:sample_rate=48000,volume=-25dB" \
       -f lavfi -i "sine=frequency=200:duration=5:sample_rate=48000,volume=0dB" \
       -f lavfi -i "sine=frequency=440:duration=5:sample_rate=48000,volume=-25dB" \
       -f lavfi -i "sine=frequency=200:duration=5:sample_rate=48000,volume=0dB" \
       -f lavfi -i "sine=frequency=440:duration=5:sample_rate=48000,volume=-25dB" \
       -f lavfi -i "sine=frequency=200:duration=5:sample_rate=48000,volume=0dB" \
       -filter_complex "[0][1][2][3][4][5]concat=n=6:v=0:a=1[aout]" \
       -map "[aout]" "$AUDIO_FILE" -y 2>/dev/null || {
    echo "[WARN] Failed to create complex audio, using simpler version..."
    # Fallback: simpler audio generation
    ffmpeg -f lavfi -i "sine=frequency=440:duration=30:sample_rate=48000" \
           "$AUDIO_FILE" -y 2>/dev/null
}

# Create video with black screen and the dynamic audio
ffmpeg -f lavfi -i color=c=black:s=1280x720:d=30:r=25 \
       -i "$AUDIO_FILE" \
       -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
       -c:a aac -b:a 128k \
       -shortest "$VIDEO_FILE" -y 2>/dev/null || {
    echo "[ERROR] Failed to create test video"
    exit 1
}

# Clean up temp audio file
rm -f "$AUDIO_FILE"

# Verify video was created
if [[ ! -f "$VIDEO_FILE" ]]; then
    echo "[ERROR] Failed to create test video"
    exit 1
fi

echo "[INFO] Test video created: action_movie.mp4 ($(du -h "$VIDEO_FILE" | cut -f1))"

# Reset VLC config to clean state - remove any existing audio filters
echo "[INFO] Resetting VLC audio configuration..."
VLC_RC="$CONFIG_DIR/vlcrc"

if [[ -f "$VLC_RC" ]]; then
    echo "[INFO] Backing up existing VLC config..."
    cp "$VLC_RC" "$CONFIG_DIR/vlcrc.backup.$(date +%s)"
    
    # Remove any existing audio filter settings to ensure clean state
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^compressor-/d' "$VLC_RC"
    sed -i '/^norm-/d' "$VLC_RC"
    sed -i '/^normalizer/d' "$VLC_RC"
    sed -i '/^volume-normalizer/d' "$VLC_RC"
    sed -i '/^audio-visual=/d' "$VLC_RC"
    
    echo "[INFO] Audio filters cleared from config"
else
    # Create minimal vlcrc if it doesn't exist
    cat > "$VLC_RC" << 'EOF'
[qt]
qt-privacy-ask=0

[core]
audio-volume=256
EOF
    echo "[INFO] Created minimal VLC config"
fi

# Set proper ownership
chown -R ga:ga "$USER_HOME/.config" "$VIDEOS_DIR" "$DESKTOP_DIR"

# Create task instruction file on desktop
cat > "$DESKTOP_DIR/TASK_INSTRUCTIONS.txt" << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║           NIGHT MODE AUDIO CONFIGURATION TASK                ║
╚══════════════════════════════════════════════════════════════╝

SCENARIO:
You want to watch action_movie.mp4 late at night in your apartment,
but it has EXTREME volume swings:
  • Dialogue is whisper-quiet (hard to hear)
  • Action scenes are EAR-SHATTERING (will wake neighbors!)

You need to enable "night mode" audio to compress dynamic range.

YOUR TASK:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

STEP 1: Open Effects Panel
  → Menu: Tools → Effects and Filters (or press Ctrl+E)

STEP 2: Enable Dynamic Range Compressor
  → Go to: Audio Effects tab
  → Find: "Compressor" section (may need to scroll)
  → Check: Enable checkbox for "Dynamic range compressor"
  
STEP 3: Enable Volume Normalizer
  → Still in Audio Effects tab
  → Look for: "Volume normalizer" or similar option
  → Check: Enable checkbox
  
STEP 4: IMPORTANT - Save Settings Persistently!
  → Close Effects window
  → Menu: Tools → Preferences
  → Click: "All" (bottom left - show all settings)
  → Navigate: Audio → Filters (in left sidebar)
  → Verify: Both "Audio normalizer" and "Dynamic range compressor" 
            are CHECKED in the list
  → Click: Save button at bottom

VERIFICATION:
✓ Dynamic range compressor enabled
✓ Volume normalizer enabled  
✓ Settings saved in VLC config file

TIME LIMIT: 120 seconds

HINT: If you can't find the filters, make sure you're in the 
      Audio Effects tab, not Video Effects!
EOF

chown ga:ga "$DESKTOP_DIR/TASK_INSTRUCTIONS.txt"

# Launch VLC with the test video
echo "[INFO] Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$VIDEO_FILE' > /tmp/vlc_night_mode_task.log 2>&1 &"

# Wait for VLC to start
if ! wait_for_process "vlc" 15; then
    echo "[ERROR] VLC failed to start"
    cat /tmp/vlc_night_mode_task.log
    exit 1
fi

# Wait for window to appear
if ! wait_for_window "VLC media player" 20; then
    echo "[ERROR] VLC window did not appear"
    exit 1
fi

# Click on center of screen to select current desktop (standard practice)
echo "[INFO] Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "[INFO] VLC window focused (WID: $wid)"
fi

# Give VLC time to fully initialize
sleep 2

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  SETUP COMPLETE - Night Mode Audio Task Ready"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📺 VLC is playing: $VIDEO_FILE"
echo "📋 Instructions: $DESKTOP_DIR/TASK_INSTRUCTIONS.txt"
echo ""
echo "🎯 AGENT GOAL:"
echo "   1. Open Tools → Effects and Filters (Ctrl+E)"
echo "   2. Enable Dynamic Range Compressor in Audio Effects"
echo "   3. Enable Volume Normalizer in Audio Effects"
echo "   4. Save settings: Tools → Preferences → Audio → Filters"
echo ""
echo "⏱  Timeout: 120 seconds"
echo "════════════════════════════════════════════════════════════"

exit 0