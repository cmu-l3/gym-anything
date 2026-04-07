#!/bin/bash
echo "=== Setting up Archival Film Sync and Restoration ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure clean slate
kill_vlc "ga"
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Documents
rm -f /home/ga/Videos/restored_archive.mp4
rm -f /home/ga/Documents/restoration_log.json

# 1. GENERATE THE GLITCHED SOURCE VIDEO
# We need a 10-second video with exactly known markers for the programmatic verifier.
# Visual Flash: Exactly at T=5.0s (frame 125). 
# Interlacing: Applied via ffmpeg interlace filter.
# Aspect Ratio: Forced to 4:3 (squished).
echo "Generating interlaced video with visual sync flash at T=5.0s..."
sudo -u ga ffmpeg -y -f lavfi -i "testsrc=size=640x480:rate=25:duration=10" \
  -vf "drawbox=x=0:y=0:w=640:h=480:color=white:t=fill:enable='between(t,5.0,5.1)',interlace=scan=tff:lowpass=0" \
  -c:v libx264 -preset ultrafast -crf 18 -flags +ilme+ildct \
  /tmp/vid_temp.mp4 2>/dev/null

# Audio Beep: Exactly at T=3.5s (1.5 seconds early).
echo "Generating audio track with sync beep at T=3.5s..."
sudo -u ga ffmpeg -y -f lavfi -i "aevalsrc=0:d=3.5" \
  -f lavfi -i "sine=frequency=1000:duration=0.1" \
  -f lavfi -i "aevalsrc=0:d=6.4" \
  -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1[aout]" \
  -map "[aout]" -c:a aac -b:a 128k -ar 44100 \
  /tmp/aud_temp.m4a 2>/dev/null

# Mux together into MKV
echo "Muxing to MKV container..."
sudo -u ga ffmpeg -y -i /tmp/vid_temp.mp4 -i /tmp/aud_temp.m4a \
  -c copy -aspect 4:3 \
  /home/ga/Videos/telecine_capture_glitched.mkv 2>/dev/null

rm -f /tmp/vid_temp.mp4 /tmp/aud_temp.m4a
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# 2. START THE ENVIRONMENT
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Videos/telecine_capture_glitched.mkv > /dev/null 2>&1 &"
sleep 3

# Maximize and focus VLC
WID=$(get_vlc_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any potential dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial state proving the application is open and ready
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="