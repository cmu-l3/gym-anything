#!/bin/bash
# Setup script for esl_language_shadowing_package task
set -e

echo "=== Setting up ESL Language Shadowing Package Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos/esl_materials
mkdir -p /home/ga/Music/shadowing_package
mkdir -p /home/ga/Documents

# 1. Create a synthetic video to represent the "restaurant_dialogue.mp4" (3 minutes)
# We use complex audio filters so there's actual sound to extract, mimicking speech dynamics.
echo "Generating source media files..."
ffmpeg -y \
  -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=180" \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=180" \
  -f lavfi -i "sine=frequency=660:sample_rate=44100:duration=180" \
  -filter_complex "[1:a][2:a]amerge=inputs=2,volume='if(between(t,15,19)+between(t,32,37)+between(t,65,71)+between(t,100,108)+between(t,135,138),0.9,0.2)':eval=frame[aout]" \
  -map 0:v -map "[aout]" \
  -c:v libx264 -preset ultrafast -b:v 1M -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ac 2 -ar 44100 \
  /home/ga/Videos/esl_materials/restaurant_dialogue.mp4 2>/dev/null

# 2. Create the 3-second silence track
ffmpeg -y \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" -t 3 \
  -c:a libmp3lame -b:a 128k \
  /home/ga/Videos/esl_materials/silence_3s.mp3 2>/dev/null

# 3. Create the timestamps document
cat > /home/ga/Videos/esl_materials/dialogue_timestamps.txt << 'TXEOF'
=== RESTAURANT DIALOGUE EXTRACT TIMESTAMPS ===
Video file: restaurant_dialogue.mp4

Please extract the following 5 phrases. To help our ESL beginners,
you MUST slow the extracted audio down to 80% speed (0.8x) while
preserving the original vocal pitch. Save each as an MP3 audio file.

Phrase 1:
- Start Time: 0:15
- End Time:   0:19
- Text: "I'd like to order the grilled salmon, please."

Phrase 2:
- Start Time: 0:32
- End Time:   0:37
- Text: "Does the salad come with dressing on the side?"

Phrase 3:
- Start Time: 1:05
- End Time:   1:11
- Text: "Could we also get some extra napkins and water?"

Phrase 4:
- Start Time: 1:40
- End Time:   1:48
- Text: "I think there's a mistake on the bill, we didn't order this."

Phrase 5:
- Start Time: 2:15
- End Time:   2:18
- Text: "Thank you, the service was excellent."

================================================
Output requirements:
- Format: MP3 (audio only)
- Speed: 80% (0.8x)
- Output directory: /home/ga/Music/shadowing_package/
- Filenames: phrase_01.mp3 through phrase_05.mp3

Don't forget to create the interleaved M3U playlist once the files are ready!
TXEOF

# Fix permissions
chown -R ga:ga /home/ga/Videos/esl_materials
chown -R ga:ga /home/ga/Music/shadowing_package

# Start VLC Application
echo "Starting VLC..."
su - ga -c "DISPLAY=:1 vlc --no-video-title-show > /dev/null 2>&1 &"
sleep 3

# Maximize the VLC window
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC" 2>/dev/null || true

# Take an initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="