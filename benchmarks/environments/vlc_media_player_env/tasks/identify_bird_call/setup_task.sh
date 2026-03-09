#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Identify Bird Call Task ==="

kill_vlc ga
sleep 1

# Create Recordings directory
mkdir -p /home/ga/Recordings
mkdir -p /home/ga/Videos
chown -R ga:ga /home/ga/Recordings
chown -R ga:ga /home/ga/Videos

# Generate 6-minute audio file with bird call at 3:45 (225 seconds)
echo "Generating 6-minute field recording with bird call..."

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found"
    exit 1
fi

# Create base ambient noise (6 minutes = 360 seconds)
# Using pink noise at low volume to simulate forest ambient sound
echo "Creating ambient base (6 minutes)..."
ffmpeg -f lavfi -i "anoisesrc=d=360:c=pink:r=44100:a=0.03" \
    -ar 44100 -ac 2 -sample_fmt s16 \
    /tmp/ambient_base.wav -y 2>/dev/null

# Create bird call sound (4 seconds)
# Frequency-modulated tone simulating a warbler call (3-5 kHz range)
# Using sine wave with vibrato effect
echo "Creating bird call (4 seconds)..."
ffmpeg -f lavfi -i "sine=frequency=4200:duration=4:sample_rate=44100" \
    -af "vibrato=f=12:d=0.8,volume=-8dB" \
    -ar 44100 -ac 2 \
    /tmp/bird_call_raw.wav -y 2>/dev/null

# Make the bird call quieter (distant) by reducing volume further
ffmpeg -i /tmp/bird_call_raw.wav -af "volume=-12dB" \
    /tmp/bird_call.wav -y 2>/dev/null

# Split ambient at 225 seconds to insert bird call
echo "Inserting bird call at 3:45 (225s)..."
ffmpeg -i /tmp/ambient_base.wav -ss 0 -t 225 -c copy /tmp/part1.wav -y 2>/dev/null
ffmpeg -i /tmp/ambient_base.wav -ss 229 -c copy /tmp/part2.wav -y 2>/dev/null

# Create concat file
cat > /tmp/concat_list.txt <<EOF
file '/tmp/part1.wav'
file '/tmp/bird_call.wav'
file '/tmp/part2.wav'
EOF

# Concatenate: part1 (0-3:45) + bird_call (3:45-3:49) + part2 (3:49-6:00)
ffmpeg -f concat -safe 0 -i /tmp/concat_list.txt -c copy \
    /home/ga/Recordings/morning_birding_2024-06-15.wav -y 2>/dev/null

# Set ownership
chown ga:ga /home/ga/Recordings/morning_birding_2024-06-15.wav

# Clean up temp files
rm -f /tmp/ambient_base.wav /tmp/part1.wav /tmp/part2.wav /tmp/bird_call.wav /tmp/bird_call_raw.wav /tmp/concat_list.txt

# Verify file was created
if [ ! -f "/home/ga/Recordings/morning_birding_2024-06-15.wav" ]; then
    echo "ERROR: Failed to create audio file"
    exit 1
fi

FILE_SIZE=$(stat -f%z "/home/ga/Recordings/morning_birding_2024-06-15.wav" 2>/dev/null || stat -c%s "/home/ga/Recordings/morning_birding_2024-06-15.wav")
echo "✅ Audio file created: $(echo "scale=1; $FILE_SIZE / 1048576" | bc 2>/dev/null || echo '?') MB"

# Don't launch VLC automatically - agent should open the file
# This makes the task more realistic

echo "=== Identify Bird Call Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open audio file: /home/ga/Recordings/morning_birding_2024-06-15.wav in VLC"
echo "  2. Scrub through to find the bird call (around 3:40-3:50)"
echo "  3. Extract a ~10-second segment containing the call"
echo "  4. Methods:"
echo "     a) Record: Seek to ~3:38, start recording, let play ~10s, stop recording"
echo "     b) Convert/Save: Use Media → Convert with time range options"
echo "  5. Save as: /home/ga/Recordings/unknown_warbler_call.{mp3,wav,ogg,flac}"
echo ""
echo "  Tip: Bird call is around 3:45 (225 seconds)"