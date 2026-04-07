#!/bin/bash
# Setup script for multilang_audio_extraction task

echo "=== Setting up Multi-Language Audio Extraction Task ==="

source /workspace/scripts/task_utils.sh || true

# 1. Clean up previous runs and ensure directories exist
pkill -f vlc 2>/dev/null || true
mkdir -p /home/ga/Videos/dubbing_deliverables
mkdir -p /home/ga/Documents
rm -rf /home/ga/Videos/dubbing_deliverables/* 2>/dev/null || true

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# 3. Create the multi-language master video
# Video: 1920x1080, 25fps, 60s test pattern with timecode
# Audio 0 (English): 440Hz tone, stereo, 48kHz
# Audio 1 (Spanish): 660Hz tone, stereo, 44.1kHz
# Audio 2 (French): 880Hz tone, mono, 44.1kHz
echo "Generating multi-track festival master..."
ffmpeg -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=25:duration=60" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=60" \
  -f lavfi -i "sine=frequency=660:sample_rate=44100:duration=60" \
  -f lavfi -i "sine=frequency=880:sample_rate=44100:duration=60" \
  -map 0:v -map 1:a -map 2:a -map 3:a \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a:0 aac -b:a:0 128k -ac:a:0 2 -ar:a:0 48000 \
  -c:a:1 aac -b:a:1 128k -ac:a:1 2 -ar:a:1 44100 \
  -c:a:2 aac -b:a:2 96k -ac:a:2 1 -ar:a:2 44100 \
  -metadata:s:a:0 language=eng -metadata:s:a:0 handler_name="English" \
  -metadata:s:a:1 language=spa -metadata:s:a:1 handler_name="Spanish" \
  -metadata:s:a:2 language=fra -metadata:s:a:2 handler_name="French" \
  /home/ga/Videos/festival_master.mp4 2>/dev/null

# 4. Create the work order document
cat > /home/ga/Documents/dubbing_work_order.txt << 'EOF'
=== STUDIO DUBBING PREPARATION - WORK ORDER ===

Source Master: /home/ga/Videos/festival_master.mp4
Output Directory: /home/ga/Videos/dubbing_deliverables/

INSTRUCTIONS:
The source master is a multiplexed MP4 containing 1 video stream and 3 distinct language audio streams (English, Spanish, French). Use VLC Media Player to analyze the streams and prepare the following deliverables:

1. audio_english.mp3
   - Extract ONLY the English audio track
   - Format: MP3 (~192 kbps)

2. audio_spanish.mp3
   - Extract ONLY the Spanish audio track
   - Format: MP3 (~192 kbps)

3. audio_french.mp3
   - Extract ONLY the French audio track
   - Format: MP3 (~192 kbps)

4. video_only.mp4
   - Create a clean copy of the video with ZERO audio streams (remove all sound).

5. english_reference.mp4
   - Create a reference copy containing the video stream and ONLY the English audio stream.

6. stream_inventory.json
   - Create a JSON file documenting the exact streams found in the original master.
   - Required format:
     {
       "source_file": "festival_master.mp4",
       "total_streams": <int>,
       "video_streams": [ { "index": <int>, "codec": "<string>", "resolution": "<WxH>", "fps": <int> } ],
       "audio_streams": [ 
         { "index": <int>, "language": "<string>", "codec": "<string>", "channels": <int>, "sample_rate": <int> }
       ]
     }
EOF

# Set ownership
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# 5. Launch VLC with the file, paused
su - ga -c "DISPLAY=:1 vlc --start-paused /home/ga/Videos/festival_master.mp4 &"
sleep 5

# Maximize and Focus VLC
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="