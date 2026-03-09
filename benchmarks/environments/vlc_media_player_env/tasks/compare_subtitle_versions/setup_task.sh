#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compare Subtitle Versions Task ==="

kill_vlc ga
sleep 1

# Create directories
mkdir -p /home/ga/Videos/subtitles
chown -R ga:ga /home/ga/Videos/subtitles

# Generate test video (60 seconds for realistic testing)
echo "Generating test video..."
if [ ! -f /home/ga/Videos/das_leben_der_anderen_2006.mkv ]; then
    ffmpeg -f lavfi -i color=c=gray:s=1280x720:d=60 \
        -f lavfi -i "sine=frequency=440:duration=60" \
        -c:v libx264 -preset ultrafast -c:a aac -b:a 128k \
        /home/ga/Videos/das_leben_der_anderen_2006.mkv -y 2>/dev/null
    echo "Generated test video (60s)"
else
    echo "Test video already exists"
fi

# Create three subtitle files with DIFFERENT timing/quality characteristics

# v1: Auto-translated (off by +2 seconds, poor translation)
cat > /home/ga/Videos/subtitles/das_leben_subtitles_v1.srt << 'EOF'
1
00:00:03,000 --> 00:00:06,000
The life of the others begins now.

2
00:05:22,000 --> 00:05:26,000
I am monitoring you very carefully person.

3
00:05:27,000 --> 00:05:31,000
What are you hiding from me about?

4
00:10:15,000 --> 00:10:19,000
The system is not correct functioning.
EOF

# v2: Professional DVD subtitle (perfect timing, good translation) ⭐ CORRECT ONE
cat > /home/ga/Videos/subtitles/das_leben_subtitles_v2.srt << 'EOF'
1
00:00:01,000 --> 00:00:04,000
"The Lives of Others" - A film by Florian Henckel von Donnersmarck

2
00:05:20,000 --> 00:05:24,000
I am monitoring you very carefully.

3
00:05:25,000 --> 00:05:29,000
What are you hiding from me?

4
00:10:13,000 --> 00:10:17,000
The system is functioning correctly.
EOF

# v3: Fan translation (off by -1 second, okay quality but mistimed)
cat > /home/ga/Videos/subtitles/das_leben_subtitles_v3.srt << 'EOF'
1
00:00:00,500 --> 00:00:03,500
"The Lives of Others" begins here.

2
00:05:19,000 --> 00:05:23,000
I'm watching you very closely.

3
00:05:24,000 --> 00:05:28,000
What are you hiding?

4
00:10:12,000 --> 00:10:16,000
The system works fine.
EOF

echo "Created three subtitle versions:"
echo "  v1: Auto-translated (poor quality, off by +2s)"
echo "  v2: DVD Professional (CORRECT - perfect timing)"
echo "  v3: Fan translation (okay quality, off by -1s)"

# Create a reference file for verification
mkdir -p /tmp/vlc_subtitle_compare_task
echo "v2" > /tmp/vlc_subtitle_compare_task/correct_answer.txt
echo "das_leben_subtitles_v2.srt" > /tmp/vlc_subtitle_compare_task/correct_filename.txt

# Set ownership
chown -R ga:ga /home/ga/Videos/subtitles
chown -R ga:ga /home/ga/Videos/das_leben_der_anderen_2006.mkv

# Launch VLC with the video
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop /home/ga/Videos/das_leben_der_anderen_2006.mkv > /tmp/vlc_subtitle_compare_task.log 2>&1 &"

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

# Pause the video at start
echo "Pausing video..."
sleep 1
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

# Seek to beginning
echo "Seeking to start..."
su - ga -c "DISPLAY=:1 xdotool key ctrl+Home" || true
sleep 0.5

echo "=== Compare Subtitle Versions Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video: /home/ga/Videos/das_leben_der_anderen_2006.mkv"
echo "  2. Three subtitle files in /home/ga/Videos/subtitles/:"
echo "     - das_leben_subtitles_v1.srt (YIFY release)"
echo "     - das_leben_subtitles_v2.srt (DVD rip)"
echo "     - das_leben_subtitles_v3.srt (BluRay)"
echo "  3. Load each subtitle (Subtitle → Add Subtitle File)"
echo "  4. Seek to 5:20 and check timing"
echo "  5. Select best subtitle and copy to:"
echo "     /home/ga/Videos/selected_subtitle.srt"