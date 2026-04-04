#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Timed Subtitles Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Documents

# Create the script text file with tutorial dialogue
cat > /home/ga/Videos/python_script.txt << 'EOF'
Welcome to this Python tutorial. Today we'll learn about NumPy arrays.
First, let's import the NumPy library using the import statement.
NumPy provides powerful array manipulation functions for scientific computing.
You can create arrays using the numpy dot array function.
Arrays can have multiple dimensions for complex data structures.
Let's look at some practical examples of array operations.
Remember to practice these concepts in your own code.
Thank you for watching this tutorial.
EOF

chown ga:ga /home/ga/Videos/python_script.txt
echo "✅ Created script file: /home/ga/Videos/python_script.txt"

# Generate tutorial video with speech audio
echo "Generating tutorial video with audio..."

# Create temporary audio file using text-to-speech
TEMP_AUDIO="/tmp/tutorial_audio.wav"

# Try to use espeak for text-to-speech
if command -v espeak &> /dev/null; then
    echo "Using espeak to generate speech audio..."
    # Generate speech with moderate speed (140 words per minute)
    espeak -f /home/ga/Videos/python_script.txt -w "$TEMP_AUDIO" -s 140 -p 50 2>/dev/null || {
        echo "⚠️ espeak failed, creating silent video"
        # Fallback: create silent video
        ffmpeg -f lavfi -i anullsrc=duration=90:sample_rate=48000:channel_layout=stereo \
               -c:a aac -b:a 128k "$TEMP_AUDIO" -y 2>/dev/null
    }
elif command -v pico2wave &> /dev/null; then
    echo "Using pico2wave for speech synthesis..."
    pico2wave -w "$TEMP_AUDIO" "$(cat /home/ga/Videos/python_script.txt)" 2>/dev/null || {
        echo "⚠️ pico2wave failed, creating silent video"
        ffmpeg -f lavfi -i anullsrc=duration=90:sample_rate=48000:channel_layout=stereo \
               -c:a aac -b:a 128k "$TEMP_AUDIO" -y 2>/dev/null
    }
else
    echo "⚠️ No TTS available, creating video with background noise"
    # Fallback: create audio with pink noise (placeholder for speech)
    ffmpeg -f lavfi -i anoisesrc=duration=90:color=pink:amplitude=0.3:sample_rate=48000 \
           -c:a aac -b:a 128k "$TEMP_AUDIO" -y 2>/dev/null
fi

# Check if audio was created
if [ ! -f "$TEMP_AUDIO" ] || [ ! -s "$TEMP_AUDIO" ]; then
    echo "ERROR: Failed to create audio file"
    exit 1
fi

echo "✅ Audio file created"

# Create video with text overlay showing "Python Tutorial" and animated background
# This makes it visually clear when playing
ffmpeg -f lavfi -i "color=c=0x2E3440:s=1280x720:d=90:r=30" \
       -i "$TEMP_AUDIO" \
       -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Python Tutorial':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2-50,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='NumPy Arrays':fontcolor=white:fontsize=32:x=(w-text_w)/2:y=(h-text_h)/2+50" \
       -c:v libx264 -preset fast -crf 22 \
       -c:a aac -b:a 128k \
       -shortest \
       /home/ga/Videos/python_tutorial.mp4 -y 2>/dev/null

# Verify video was created
if [ ! -f /home/ga/Videos/python_tutorial.mp4 ] || [ ! -s /home/ga/Videos/python_tutorial.mp4 ]; then
    echo "ERROR: Failed to create video file"
    exit 1
fi

echo "✅ Video created: /home/ga/Videos/python_tutorial.mp4"

# Clean up temporary audio
rm -f "$TEMP_AUDIO"

# Set ownership
chown -R ga:ga /home/ga/Videos/

# Create detailed instructions file
cat > /home/ga/Documents/subtitle_task_instructions.txt << 'EOF'
═══════════════════════════════════════════════════════════════
TASK: Create Timed Subtitles for Python Tutorial Video
═══════════════════════════════════════════════════════════════

OBJECTIVE:
Create an SRT subtitle file with proper timing for the tutorial video.

FILES:
  Video:  /home/ga/Videos/python_tutorial.mp4  (90 seconds)
  Script: /home/ga/Videos/python_script.txt    (dialogue text)
  Output: /home/ga/Videos/python_tutorial.srt  (YOU CREATE THIS)

REQUIREMENTS:
  ✓ Valid SRT format
  ✓ At least 5 subtitle segments
  ✓ Proper timing synchronized to speech
  ✓ Each segment has text content
  ✓ Chronological order

SRT FORMAT EXAMPLE:
─────────────────────────────────────────────────────────────
1
00:00:05,000 --> 00:00:08,500
Welcome to this Python tutorial.

2
00:00:08,500 --> 00:00:12,000
Today we'll learn about NumPy arrays.

3
00:00:12,000 --> 00:00:16,500
First, let's import the NumPy library using the import statement.
─────────────────────────────────────────────────────────────

STEPS:
  1. Open the video in VLC: /home/ga/Videos/python_tutorial.mp4
  2. Read the script: /home/ga/Videos/python_script.txt
  3. Play the video and note when each line is spoken
  4. Create the SRT file with proper timing
  5. Save as: /home/ga/Videos/python_tutorial.srt

TIPS:
  • Use VLC's time display to note timestamps
  • Break long sentences into 2-3 subtitle segments
  • Don't start at 0:00:00 - wait for speech to begin
  • Each subtitle should be visible for 2-4 seconds
  • Use Space to pause/play, Shift+Right to skip forward

TOOLS:
  • VLC for playback and timing
  • Any text editor (gedit, nano, vim, mousepad)
  • Calculator app for timing calculations (optional)

═══════════════════════════════════════════════════════════════
EOF

chown ga:ga /home/ga/Documents/subtitle_task_instructions.txt
echo "✅ Instructions created: /home/ga/Documents/subtitle_task_instructions.txt"

# Launch VLC with the tutorial video (paused initially)
echo "Launching VLC with tutorial video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused /home/ga/Videos/python_tutorial.mp4 > /tmp/vlc_subtitle_create_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_subtitle_create_task.log
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

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for video to fully load
sleep 2

echo "=== Create Timed Subtitles Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  1. VLC is ready with the tutorial video (paused)"
echo "  2. Review the script at: /home/ga/Videos/python_script.txt"
echo "  3. Play the video and note timestamps for each line"
echo "  4. Create SRT file: /home/ga/Videos/python_tutorial.srt"
echo "  5. Format: subtitle number, timecode, text, blank line"
echo ""
echo "  Example SRT entry:"
echo "    1"
echo "    00:00:05,000 --> 00:00:08,500"
echo "    Welcome to this Python tutorial."
echo "    "
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Full instructions: /home/ga/Documents/subtitle_task_instructions.txt"
echo ""