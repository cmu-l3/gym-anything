#!/bin/bash
echo "=== Setting up Fleet Dashcam PiP Synchronization task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos
rm -f /home/ga/Videos/front_camera.mp4
rm -f /home/ga/Videos/cabin_camera.mp4
rm -f /home/ga/Videos/incident_composite.mp4
rm -f /tmp/task_result.json

# Ground Truth variables (hidden from agent)
FRONT_FLASH_START=25.0
FRONT_FLASH_END=25.5
CABIN_FLASH_START=38.0
CABIN_FLASH_END=38.5

echo "Generating front_camera.mp4 (1920x1080)..."
# Front camera: 60 seconds, 1920x1080, silent. Red flash at t=25
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=60" \
  -vf "drawtext=text='FRONT DASHCAM - VEHICLE 402':x=50:y=50:fontsize=48:fontcolor=white:box=1:boxcolor=black@0.5,drawbox=x=0:y=0:w=1920:h=1080:color=red:t=fill:enable='between(t,${FRONT_FLASH_START},${FRONT_FLASH_END})'" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p /home/ga/Videos/front_camera.mp4 2>/dev/null

echo "Generating cabin_camera.mp4 (1280x720)..."
# Cabin camera: 60 seconds, 1280x720, with audio. Blue flash at t=38
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=60" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=60" \
  -vf "drawtext=text='CABIN CAMERA - DRIVER VIEW':x=50:y=50:fontsize=48:fontcolor=white:box=1:boxcolor=black@0.5,drawbox=x=0:y=0:w=1280:h=720:color=blue:t=fill:enable='between(t,${CABIN_FLASH_START},${CABIN_FLASH_END})'" \
  -af "volume='if(between(t,${CABIN_FLASH_START},${CABIN_FLASH_END}),1.0,0.1)':eval=frame" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -b:a 128k -ac 2 /home/ga/Videos/cabin_camera.mp4 2>/dev/null

# Ensure proper permissions
chown -R ga:ga /home/ga/Videos

# Start VLC to confirm environment is ready, but without loading files to force discovery
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
    sleep 2
fi

# Maximize the VLC window
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="