#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compare Voice Takes Task ==="

kill_vlc ga
sleep 1

# Create directory structure
PROJECT_DIR="/home/ga/VoiceRecordings/ProjectApollo"
mkdir -p "$PROJECT_DIR"
chown -R ga:ga /home/ga/VoiceRecordings

# Install espeak if not available (for TTS generation)
if ! command -v espeak &> /dev/null; then
    echo "Installing espeak for audio generation..."
    apt-get update -qq
    apt-get install -y espeak &> /dev/null || echo "espeak install failed, will try alternative"
fi

# The line being recorded (for script.txt)
LINE_TEXT="Houston, we have a problem. Repeat: we have a problem with the oxygen system."

# Create script file
echo "$LINE_TEXT" > "$PROJECT_DIR/script.txt"
chown ga:ga "$PROJECT_DIR/script.txt"

# Generate base audio using espeak (or download pre-recorded if espeak fails)
BASE_AUDIO="$PROJECT_DIR/base_audio.wav"

if command -v espeak &> /dev/null; then
    # Generate base audio with espeak
    espeak -v en-us -s 160 -p 50 -w "$BASE_AUDIO" "$LINE_TEXT" 2>/dev/null || {
        echo "espeak failed, using fallback method..."
        # Fallback: create silent audio as placeholder
        ffmpeg -f lavfi -i "sine=frequency=440:duration=8" -ar 44100 "$BASE_AUDIO" -y 2>/dev/null
    }
else
    # Fallback: download or create silent audio
    echo "Creating fallback audio..."
    ffmpeg -f lavfi -i "anoisesrc=duration=8:color=white:seed=0:sample_rate=44100" -filter:a "volume=0.05" "$BASE_AUDIO" -y 2>/dev/null
fi

# Ensure base audio exists
if [ ! -f "$BASE_AUDIO" ]; then
    echo "ERROR: Failed to create base audio"
    exit 1
fi

# Generate Take 1: Reduced volume (-8dB, slightly quiet)
echo "Generating Take 1 (quiet)..."
ffmpeg -i "$BASE_AUDIO" -filter:a "volume=-8dB" "$PROJECT_DIR/line_042_take1.mp3" -y 2>/dev/null

# Generate Take 2: Good quality but with a click at 3 seconds
echo "Generating Take 2 (with click artifact)..."
# Create a click sound
CLICK_FILE="/tmp/click.wav"
ffmpeg -f lavfi -i "sine=frequency=1000:duration=0.05" -filter:a "volume=0.5" "$CLICK_FILE" -y 2>/dev/null

# Mix the click into the audio at 3 seconds
ffmpeg -i "$BASE_AUDIO" -i "$CLICK_FILE" -filter_complex \
    "[0:a]apad[a0];[1:a]adelay=3000|3000[a1];[a0][a1]amix=inputs=2:duration=first" \
    "$PROJECT_DIR/line_042_take2.mp3" -y 2>/dev/null

rm -f "$CLICK_FILE"

# Generate Take 3: Clean copy (BEST TAKE)
echo "Generating Take 3 (best/clean)..."
ffmpeg -i "$BASE_AUDIO" "$PROJECT_DIR/line_042_take3.mp3" -y 2>/dev/null

# Generate Take 4: Too fast/rushed (1.3x speed)
echo "Generating Take 4 (too fast)..."
ffmpeg -i "$BASE_AUDIO" -filter:a "atempo=1.3" "$PROJECT_DIR/line_042_take4.mp3" -y 2>/dev/null

# Clean up base audio
rm -f "$BASE_AUDIO"

# Create empty take_selection.txt file
touch "$PROJECT_DIR/take_selection.txt"
chown ga:ga "$PROJECT_DIR/take_selection.txt"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"

# Verify all files were created
echo "Verifying generated files..."
for i in 1 2 3 4; do
    TAKE_FILE="$PROJECT_DIR/line_042_take${i}.mp3"
    if [ -f "$TAKE_FILE" ]; then
        SIZE=$(stat -f%z "$TAKE_FILE" 2>/dev/null || stat -c%s "$TAKE_FILE" 2>/dev/null)
        echo "✅ Take $i created (${SIZE} bytes)"
    else
        echo "❌ Take $i FAILED"
    fi
done

# Launch VLC (don't auto-play, let agent navigate)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_voice_takes_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Compare Voice Takes Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Audio takes are in: /home/ga/VoiceRecordings/ProjectApollo/"
echo "  2. Review all 4 takes:"
echo "     - line_042_take1.mp3 (slightly quiet)"
echo "     - line_042_take2.mp3 (has artifact at 3s)"
echo "     - line_042_take3.mp3 (clean, best)"
echo "     - line_042_take4.mp3 (too fast)"
echo "  3. Open each file in VLC (Ctrl+O or Media → Open File)"
echo "  4. Compare quality: volume, artifacts, pacing, clarity"
echo "  5. Document findings in: /home/ga/VoiceRecordings/ProjectApollo/take_selection.txt"
echo "  6. Clearly identify best take (take 3) with reasoning"