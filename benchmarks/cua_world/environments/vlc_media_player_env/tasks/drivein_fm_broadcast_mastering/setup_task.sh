#!/bin/bash
# Setup script for drivein_fm_broadcast_mastering task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up drivein_fm_broadcast_mastering task ==="

kill_vlc

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Music
mkdir -p /home/ga/Documents

echo "Generating highly dynamic raw action trailer video..."
# We create a 30-second video with extreme dynamic range to simulate an action movie
# 0-10s: Quiet dialogue (simulated by low volume sine wave)
# 10-20s: Loud explosion/action (simulated by high volume white noise)
# 20-30s: Quiet dialogue (simulated by low volume sine wave)
ffmpeg -y \
  -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=30" \
  -f lavfi -i "sine=frequency=440:duration=10" \
  -f lavfi -i "anoisesrc=c=pink:duration=10" \
  -f lavfi -i "sine=frequency=440:duration=10" \
  -filter_complex "[1:a]volume=0.05[a1]; [2:a]volume=0.9[a2]; [3:a]volume=0.05[a3]; [a1][a2][a3]concat=n=3:v=0:a=1[aout]" \
  -map 0:v -map "[aout]" \
  -c:v libx264 -preset ultrafast -b:v 1M \
  -c:a aac -b:a 192k -ac 2 -ar 48000 \
  /home/ga/Videos/action_trailer_raw_mix.mkv 2>/dev/null

echo "Generating uncompressed baseline for acoustic verification..."
# We generate what the file sounds like if the agent just extracts it WITHOUT the compressor filter.
# This serves as the ground truth baseline. The compressor will raise the mean volume (makeup gain)
# and lower the crest factor (max - mean).
ffmpeg -y -i /home/ga/Videos/action_trailer_raw_mix.mkv \
  -vn -c:a libmp3lame -b:a 128k -ac 1 -ar 44100 \
  /tmp/baseline_audio.mp3 2>/dev/null

# Create work order instructions
cat > /home/ga/Documents/fm_work_order.txt << 'WOEOF'
FM BROADCAST MASTERING INSTRUCTIONS
-----------------------------------
Source File: /home/ga/Videos/action_trailer_raw_mix.mkv

The source has massive volume spikes. For our FM transmitter, we need a squashed, flat audio file.

REQUIREMENTS:
1. Strip the video stream completely.
2. Downmix audio to Mono (1 channel).
3. Set sample rate to 44100 Hz.
4. Set format to MP3 at 128 kbps.
5. CRITICAL: You MUST enable the "Dynamic range compressor" in the audio filter settings to squash the peaks and boost the quiet dialogue.
6. Save the output to: /home/ga/Music/fm_broadcast_audio.mp3
7. Create a JSON report at /home/ga/Documents/fm_specs.json with:
   {
      "filename": "fm_broadcast_audio.mp3",
      "channels": 1,
      "sample_rate": 44100,
      "compression_applied": true
   }
WOEOF

chown -R ga:ga /home/ga/Videos /home/ga/Music /home/ga/Documents

# Launch VLC (empty state) and maximize
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 3

DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="