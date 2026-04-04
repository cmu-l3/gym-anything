#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Reduce Tape Hiss Task ==="

kill_vlc ga
sleep 1

# Ensure necessary directories exist
mkdir -p /home/ga/Music
mkdir -p /home/ga/.config/vlc
mkdir -p /home/ga/Desktop

# Reset VLC audio filter settings to ensure clean state
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing audio filter settings
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^compressor-/d' "$VLC_RC"
    sed -i '/^norm-/d' "$VLC_RC"
    sed -i '/^spatializer-/d' "$VLC_RC"
    sed -i '/^equalizer-/d' "$VLC_RC"
    echo "Audio filters reset to default"
fi

# Generate noisy audio file (simulate digitized cassette with hiss)
echo "Generating noisy audio file (simulating digitized cassette tape)..."

# Create script to generate audio with noise
cat > /tmp/generate_noisy_audio.sh << 'EOFGEN'
#!/bin/bash
set -e

# Generate base audio - mix of tones simulating speech frequencies (200-3000 Hz)
ffmpeg -f lavfi -i "sine=frequency=300:duration=30" \
  -f lavfi -i "sine=frequency=500:duration=30" \
  -f lavfi -i "sine=frequency=800:duration=30" \
  -f lavfi -i "sine=frequency=1200:duration=30" \
  -filter_complex "[0:a][1:a][2:a][3:a]amerge=inputs=4,pan=mono|c0=0.25*c0+0.25*c1+0.25*c2+0.25*c3,volume=0.4[speech]" \
  -map "[speech]" -y /tmp/clean_base.wav 2>/dev/null

# Generate white noise (tape hiss) at moderate amplitude
ffmpeg -f lavfi -i "anoisesrc=duration=30:color=white:amplitude=0.25" \
  -y /tmp/hiss_noise.wav 2>/dev/null

# Mix speech with hiss noise
ffmpeg -i /tmp/clean_base.wav -i /tmp/hiss_noise.wav \
  -filter_complex "[0:a][1:a]amerge=inputs=2,pan=mono|c0=0.7*c0+0.3*c1[mixed]" \
  -map "[mixed]" -y /tmp/noisy_mix.wav 2>/dev/null

# Convert to MP3 for realistic scenario
ffmpeg -i /tmp/noisy_mix.wav -codec:a libmp3lame -b:a 192k \
  -y /home/ga/Music/grandma_birthday_1995_digitized.mp3 2>/dev/null

# Cleanup temp files
rm -f /tmp/clean_base.wav /tmp/hiss_noise.wav /tmp/noisy_mix.wav

echo "✓ Noisy audio file generated"
EOFGEN

chmod +x /tmp/generate_noisy_audio.sh

# Run the generation script
if /tmp/generate_noisy_audio.sh; then
    echo "✅ Noisy audio file created successfully"
    ls -lh /home/ga/Music/grandma_birthday_1995_digitized.mp3
else
    echo "⚠️ Audio generation failed, creating fallback..."
    # Fallback: copy existing sample and add note
    if [ -f /home/ga/Music/sample_audio.mp3 ]; then
        cp /home/ga/Music/sample_audio.mp3 /home/ga/Music/grandma_birthday_1995_digitized.mp3
    else
        # Ultimate fallback: generate simple tone with noise
        ffmpeg -f lavfi -i "sine=frequency=440:duration=30" \
          -f lavfi -i "anoisesrc=duration=30:color=white:amplitude=0.3" \
          -filter_complex "[0:a][1:a]amix=inputs=2:duration=first" \
          -codec:a libmp3lame -b:a 192k \
          /home/ga/Music/grandma_birthday_1995_digitized.mp3 2>/dev/null
    fi
fi

# Set ownership
chown -R ga:ga /home/ga/Music
chown -R ga:ga /home/ga/.config/vlc
chown -R ga:ga /home/ga/Desktop

# Create task instruction file on desktop
cat > /home/ga/Desktop/TASK_INSTRUCTIONS.txt << 'EOFINST'
╔══════════════════════════════════════════════════════════════╗
║  🎙️  AUDIO RESTORATION TASK: Remove Tape Hiss               ║
╚══════════════════════════════════════════════════════════════╝

SCENARIO:
You have a digitized cassette recording from 1995 with significant 
tape hiss. You need to clean it up using VLC's audio filters before 
sharing with family.

FILE LOCATION:
📁 /home/ga/Music/grandma_birthday_1995_digitized.mp3

YOUR TASKS:
1. The audio file will start playing automatically
2. Listen to the background hiss/static
3. Open Audio Effects:
   → Tools → Effects and Filters (or press Ctrl+E)
4. Go to "Audio Effects" tab
5. Enable audio filters to reduce hiss. Try:
   ✓ "Compressor" - reduces dynamic range and background noise
   ✓ "Volume normalizer" - helps even out levels
   ✓ "Spatializer" - can help separate signal from noise
6. Adjust filter parameters using sliders
7. Close the dialog - settings will auto-save

VERIFICATION:
✅ VLC configuration will be checked for enabled audio filters
✅ Filter settings should show noise reduction parameters
✅ Configuration should persist in vlcrc file

HINTS:
• The Audio Effects panel has multiple tabs - explore them
• Dynamic range compression is very effective for noise reduction
• You can enable multiple filters at once
• Don't over-filter or speech will sound muffled
• Changes are applied in real-time - listen to the result
• Settings persist after closing the Effects window

GOAL:
Reduce the constant background hiss while keeping voices clear.
EOFINST

chown ga:ga /home/ga/Desktop/TASK_INSTRUCTIONS.txt

# Launch VLC with the noisy audio file and RC interface
echo "Launching VLC with noisy audio file..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 /home/ga/Music/grandma_birthday_1995_digitized.mp3 > /tmp/vlc_noise_reduction_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_noise_reduction_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait a moment for VLC to fully initialize
sleep 2

echo "=== Reduce Tape Hiss Task Setup Complete ==="
echo ""
echo "📋 Task Summary:"
echo "  • Audio file: /home/ga/Music/grandma_birthday_1995_digitized.mp3"
echo "  • Task: Apply audio filters to reduce tape hiss"
echo "  • Access: Tools → Effects and Filters (Ctrl+E)"
echo "  • Filters: Compressor, Normalizer, Spatializer, or Equalizer"
echo "  • Goal: Reduce hiss while preserving speech clarity"
echo ""
echo "💡 Instructions available on desktop: TASK_INSTRUCTIONS.txt"