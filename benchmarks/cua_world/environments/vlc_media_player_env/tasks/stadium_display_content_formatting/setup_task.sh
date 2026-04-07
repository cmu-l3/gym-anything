#!/bin/bash
# Setup script for stadium_display_content_formatting task
set -e

echo "=== Setting up stadium_display_content_formatting task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -f vlc 2>/dev/null || true
rm -rf /home/ga/Videos/stadium_ready 2>/dev/null || true
rm -f /home/ga/Documents/deployment.json 2>/dev/null || true

# Create required directories
mkdir -p /home/ga/Videos/stadium_ready
mkdir -p /home/ga/Documents

echo "Generating source video..."
# Generate a 60-second "commercial" workprint using ffmpeg
# Contains visual markers for the "action" sequence between 0:25 and 0:40
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=60" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=60" \
  -vf "drawbox=x=0:y=0:w=1920:h=1080:color=black@0.8:t=fill, \
       drawtext=text='ENERGY DRINK COMMERCIAL - WORKPRINT':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=100, \
       drawtext=text='SCENE 1: INTRODUCTION':fontcolor=yellow:fontsize=48:x=(w-text_w)/2:y=200:enable='between(t,0,25)', \
       drawtext=text='SCENE 2: HIGH ACTION':fontcolor=red:fontsize=96:x=(w-text_w)/2:y=500:enable='between(t,25,40)', \
       drawtext=text='SCENE 3: PRODUCT SHOT':fontcolor=green:fontsize=48:x=(w-text_w)/2:y=200:enable='between(t,40,60)', \
       drawtext=text='%{pts\:hms}':fontcolor=white:fontsize=48:x=w-300:y=h-100:box=1:boxcolor=black@0.5" \
  -c:v libx264 -preset ultrafast -b:v 4M -pix_fmt yuv420p \
  -c:a aac -b:a 192k \
  /home/ga/Videos/energy_drink_commercial.mp4 2>/dev/null

echo "Creating technical brief..."
# Create the display specifications document
cat > /home/ga/Documents/display_specs.txt << 'SPECEOF'
=== STADIUM DISPLAY TECHNICAL SPECIFICATIONS ===
Event: Weekend Championship
Source Asset: /home/ga/Videos/energy_drink_commercial.mp4

INSTRUCTIONS:
We need to extract the high-action segment from the sponsor's commercial.
Target Segment: Exactly 0:25 to 0:40 (15 seconds total duration).

All deliverables must be saved to: /home/ga/Videos/stadium_ready/
No audio should be present in the final deliverables.

1. JUMBOTRON DELIVERABLE
   Filename: jumbotron_ad.mp4
   Resolution: 1280x720 (Downscaled from 1920x1080)
   Audio: None (Strip audio stream)
   
2. LED RIBBON BOARD DELIVERABLE
   Filename: ribbon_board_ad.mp4
   Resolution: 1920x120
   Geometry: Exact vertical center strip of the 1080p source video.
   Crop parameters: Width=1920, Height=120, X-offset=0, Y-offset=480
   Audio: None (Strip audio stream)

3. DEPLOYMENT MANIFEST
   Filename: /home/ga/Documents/deployment.json
   Format required exactly as follows:

{
  "event": "Weekend Championship",
  "source_video": "energy_drink_commercial.mp4",
  "displays": [
    {
      "display_type": "Jumbotron",
      "filename": "jumbotron_ad.mp4",
      "resolution": "1280x720",
      "duration_seconds": 15,
      "audio_included": false
    },
    {
      "display_type": "Ribbon Board",
      "filename": "ribbon_board_ad.mp4",
      "resolution": "1920x120",
      "duration_seconds": 15,
      "audio_included": false
    }
  ]
}
SPECEOF

# Fix permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC with the source video
su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Videos/energy_drink_commercial.mp4 &" 2>/dev/null || true
sleep 3

# Maximize the VLC window
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot for evidence
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="