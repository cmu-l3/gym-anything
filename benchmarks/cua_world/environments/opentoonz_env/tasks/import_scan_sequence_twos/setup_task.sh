#!/bin/bash
set -e
echo "=== Setting up import_scan_sequence_twos task ==="

# Define paths
INPUT_DIR="/home/ga/OpenToonz/inputs/muybridge_horse"
OUTPUT_DIR="/home/ga/OpenToonz/output/twos_import"

# 1. Clean up and prepare directories
rm -rf "$INPUT_DIR" "$OUTPUT_DIR"
su - ga -c "mkdir -p $INPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Generate Input Data (Synthetic 'Scan' Sequence)
# We generate 12 frames of a moving shape to ensure distinct visual differences between frames.
# This avoids reliance on external downloads and ensures pixel-perfect inputs.
echo "Generating input image sequence..."
python3 -c "
from PIL import Image, ImageDraw, ImageFont
import os

output_dir = '$INPUT_DIR'
num_frames = 12
width, height = 720, 576

# Create frames
for i in range(num_frames):
    img = Image.new('RGB', (width, height), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)
    
    # Draw a moving black circle (simulating the subject)
    # Moves horizontally across the screen
    radius = 50
    x_start = 100
    x_end = 600
    step = (x_end - x_start) / (num_frames - 1)
    
    x = x_start + (i * step)
    y = height // 2
    
    # Draw circle
    draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill='black')
    
    # Draw frame number (to make frames strictly unique)
    draw.text((10, 10), f'Frame {i+1}', fill='black')
    
    # Save
    filename = f'frame_{i+1:04d}.png'
    img.save(os.path.join(output_dir, filename))

print(f'Generated {num_frames} frames in {output_dir}')
"

# Set permissions
chown -R ga:ga "/home/ga/OpenToonz/inputs"
chown -R ga:ga "/home/ga/OpenToonz/output"

# 3. Setup OpenToonz
# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure OpenToonz is running and clean
pkill -f opentoonz 2>/dev/null || true
sleep 1

echo "Starting OpenToonz..."
# Launch empty OpenToonz
su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" > /dev/null 2>&1 || su - ga -c "DISPLAY=:1 opentoonz &" > /dev/null 2>&1
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "OpenToonz window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss startup dialogs (common in OpenToonz)
sleep 5
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="