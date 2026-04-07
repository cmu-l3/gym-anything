#!/bin/bash
echo "=== Setting up Retro Speedrun Capture Restoration task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
pkill -f vlc > /dev/null 2>&1 || true
rm -rf /home/ga/Videos/raw_capture
rm -rf /home/ga/Videos/leaderboard_submission
rm -f /home/ga/Documents/leaderboard_rules.txt

# Create necessary directories
mkdir -p /home/ga/Videos/raw_capture
mkdir -p /home/ga/Videos/leaderboard_submission
mkdir -p /home/ga/Documents

# Generate the raw retro speedrun capture (45s, 720x480, interlaced, with 16px black borders on all sides)
# Includes "VICTORY" text at the 25-second mark for the thumbnail capture.
echo "Generating raw speedrun capture..."
ffmpeg -y \
  -f lavfi -i "testsrc2=size=720x480:rate=30:duration=45" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=45" \
  -vf "drawtext=text='SPEEDRUN CAPTURE':x=(w-tw)/2:y=50:fontsize=36:fontcolor=white,drawtext=text='VICTORY':x=(w-tw)/2:y=(h-th)/2:fontsize=72:fontcolor=yellow:enable='between(t,24,26)',drawbox=x=0:y=0:w=720:h=16:color=black:t=fill,drawbox=x=0:y=464:w=720:h=16:color=black:t=fill,drawbox=x=0:y=0:w=16:h=480:color=black:t=fill,drawbox=x=704:y=0:w=16:h=480:color=black:t=fill" \
  -c:v mpeg2video -b:v 3M -c:a mp2 -b:a 192k \
  /home/ga/Videos/raw_capture/speedrun_raw.mpg 2>/dev/null

# Create the leaderboard rules document
cat > /home/ga/Documents/leaderboard_rules.txt << 'EOF'
=== SPEEDRUN LEADERBOARD SUBMISSION GUIDELINES ===

RAW CAPTURES WILL BE REJECTED. You must format your video before submitting.

1. OVERSCAN CROPPING
   Most retro consoles output a 720x480 signal but the active picture is smaller. 
   You MUST crop 16 pixels from ALL sides (Top, Bottom, Left, Right).
   Final resolution MUST be exactly 688x448.

2. VIDEO FORMAT
   - Container: MP4
   - Video Codec: H.264
   - Audio Codec: AAC
   - Scan type: Progressive (You must deinterlace the raw capture!)

3. ANTI-CHEAT AUDIO 
   Provide a standalone MP3 file of the run's audio (no video stream) so our 
   moderators can perform waveform analysis to detect splicers.

4. THUMBNAIL
   Provide a PNG snapshot of the exact moment the "VICTORY" screen appears 
   (around the 0:25 mark). Must match the cropped 688x448 resolution.

5. MANIFEST
   Include a manifest.json with your runner name, original resolution, 
   cropped resolution, and deinterlaced boolean flag.
EOF

# Fix permissions
chown -R ga:ga /home/ga/Videos/raw_capture
chown -R ga:ga /home/ga/Videos/leaderboard_submission
chown -R ga:ga /home/ga/Documents

# Open VLC with the file paused so the agent sees it immediately
su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Videos/raw_capture/speedrun_raw.mpg --start-time=0.0 --pause &" 2>/dev/null || true

# Wait for VLC to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "VLC"; then
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC" 2>/dev/null || true

# Capture initial state
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="