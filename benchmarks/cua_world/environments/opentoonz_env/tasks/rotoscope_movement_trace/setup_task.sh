#!/bin/bash
set -e
echo "=== Setting up rotoscope_movement_trace task ==="

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Directories
REF_DIR="/home/ga/OpenToonz/samples/bounce_ref"
OUTPUT_DIR="/home/ga/OpenToonz/output/rotoscope_test"
PROJECTS_DIR="/home/ga/OpenToonz/projects"

# Cleanup previous run artifacts
rm -rf "$OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"
su - ga -c "mkdir -p $REF_DIR"
# Ensure project directory exists for saving levels
su - ga -c "mkdir -p $PROJECTS_DIR"

# Generate Reference Data (Bouncing Ball Image Sequence)
# We generate this programmatically to ensure a clean, consistent "real" physics reference.
echo "Generating reference sequence..."
python3 -c "
from PIL import Image, ImageDraw
import os
import math

output_dir = '$REF_DIR'
width, height = 720, 540
frames = 24
ball_radius = 20

# Parabolic path parameters
start_x, start_y = 50, 100
end_x, end_y = 670, 100
ground_y = 450
mid_x = (start_x + end_x) / 2
apex_y = 50

for i in range(frames):
    img = Image.new('RGB', (width, height), (0, 0, 0)) # Black background
    draw = ImageDraw.Draw(img)
    
    # Calculate t (0 to 1)
    t = i / (frames - 1)
    
    # Linear X
    x = start_x + (end_x - start_x) * t
    
    # Parabolic Y (y = a(x-h)^2 + k)
    # Normalized parabola: 4 * (x - 0.5)^2 maps 0..1 to 1..0..1 (flipped)
    # We want 0..1 to 0..1..0 for height
    parabola = 1 - 4 * ((t - 0.5) ** 2)
    y = ground_y - (ground_y - apex_y) * parabola
    
    # Draw Ball (White)
    draw.ellipse((x - ball_radius, y - ball_radius, x + ball_radius, y + ball_radius), fill=(255, 255, 255))
    
    # Save frame
    filename = f'bounce.{i+1:04d}.png'
    img.save(os.path.join(output_dir, filename))
"

# Set permissions
chown -R ga:ga "$REF_DIR"

# Record initial file count in projects dir to detect new levels later
find "$PROJECTS_DIR" -type f | wc -l > /tmp/initial_project_files_count.txt

# Launch OpenToonz
echo "Starting OpenToonz..."
if ! pgrep -f "opentoonz" > /dev/null; then
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
    sleep 5 # Allow full initialization
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any startup popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Reference data located at: $REF_DIR"