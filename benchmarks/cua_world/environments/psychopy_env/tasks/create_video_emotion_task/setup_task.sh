#!/bin/bash
echo "=== Setting up create_video_emotion_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and nonce
record_task_start
generate_nonce

# Clean up previous runs
rm -rf /home/ga/PsychoPyExperiments/emotion_task 2>/dev/null || true
rm -rf /home/ga/assets/videos 2>/dev/null || true

# Create assets directory
mkdir -p /home/ga/assets/videos
chown ga:ga /home/ga/assets/videos

# Generate valid MP4 assets using Python/OpenCV
# This ensures the files are technically valid video containers that PsychoPy can open
echo "Generating video assets..."
python3 -c "
import cv2
import numpy as np
import os

def create_video(filename, text, color):
    # Create a valid mp4 file (1280x720, 24fps, 3 seconds)
    height, width = 720, 1280
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(filename, fourcc, 24.0, (width, height))
    
    for i in range(48): # 2 seconds
        frame = np.full((height, width, 3), color, dtype=np.uint8)
        # Bouncing text
        x = int(100 + i * 10)
        y = int(360 + np.sin(i/5)*50)
        cv2.putText(frame, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 3, (255, 255, 255), 5)
        out.write(frame)
    out.release()

os.chdir('/home/ga/assets/videos')
# Colors are BGR
create_video('joy.mp4', 'JOY - POSITIVE', (0, 200, 200))      # Yellow-ish
create_video('sadness.mp4', 'SADNESS - NEGATIVE', (100, 50, 0)) # Blue-ish
create_video('neutral.mp4', 'NEUTRAL - CALM', (128, 128, 128)) # Grey
"

chown -R ga:ga /home/ga/assets

# Launch PsychoPy
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 40
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Video assets prepared in: /home/ga/assets/videos/"