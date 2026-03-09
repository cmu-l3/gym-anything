#!/bin/bash
set -e
echo "=== Setting up Exoplanet Scatter Plot Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ================================================================
# 1. GENERATE RANDOM DATASET (Real-time generation prevents caching)
# ================================================================
CSV_PATH="/home/ga/Desktop/exoplanets.csv"
echo "Generating dataset at $CSV_PATH..."

python3 -c "
import csv
import random

header = ['id', 'x', 'y', 'z', 'radius', 'habitable']
rows = []
start_id = 101

# Generate 50 planets
for i in range(50):
    pid = start_id + i
    # Scatter within a 30x30x30 cube centered at origin
    x = round(random.uniform(-15.0, 15.0), 2)
    y = round(random.uniform(-15.0, 15.0), 2)
    z = round(random.uniform(-15.0, 15.0), 2)
    # Radius 0.5 to 2.5 Earth radii
    radius = round(random.uniform(0.5, 2.5), 2)
    # 20% chance of being habitable
    habitable = 'Yes' if random.random() < 0.2 else 'No'
    
    rows.append([pid, x, y, z, radius, habitable])

with open('$CSV_PATH', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(header)
    writer.writerows(rows)
    
print(f'Generated {len(rows)} rows.')
"

# Set permissions so agent can read it
chown ga:ga "$CSV_PATH"

# ================================================================
# 2. LAUNCH BLENDER
# ================================================================
echo "Launching Blender..."

# Ensure Projects dir exists
mkdir -p /home/ga/BlenderProjects
chown ga:ga /home/ga/BlenderProjects

# Remove output file if it exists from previous run
rm -f "/home/ga/BlenderProjects/exoplanet_viz.blend"

# Launch Blender with default scene
launch_blender_clean()

# Wait for Blender
wait_for_blender

# Maximize window
maximize_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="