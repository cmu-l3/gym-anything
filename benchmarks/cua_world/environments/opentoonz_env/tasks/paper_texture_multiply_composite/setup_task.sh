#!/bin/bash
set -e
echo "=== Setting up paper_texture_multiply_composite task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
su - ga -c "mkdir -p /home/ga/OpenToonz/inputs"
su - ga -c "mkdir -p /home/ga/OpenToonz/output/textured_composite"

# Clear previous outputs
rm -rf /home/ga/OpenToonz/output/textured_composite/*

# Ensure source scene exists
if [ ! -f "/home/ga/OpenToonz/samples/dwanko_run.tnz" ]; then
    echo "Restoring sample scene..."
    # Fallback if sample is missing (should be there from env setup)
    cp /home/ga/OpenToonz/samples/dwanko_run.tnz.bak /home/ga/OpenToonz/samples/dwanko_run.tnz 2>/dev/null || true
fi

# Generate the Parchment Texture using Python (Pillow)
# We generate it here to ensure it's high quality and available
echo "Generating parchment texture..."
cat > /tmp/gen_texture.py << 'EOF'
import numpy as np
from PIL import Image

# Create a 2000x2000 texture (larger than HD to require scaling)
width, height = 2000, 2000

# Base color (Paper beige)
base_color = np.array([245, 235, 215], dtype=np.uint8)

# Generate noise
noise = np.random.normal(0, 15, (height, width, 3))
texture = np.clip(base_color + noise, 0, 255).astype(np.uint8)

# Add some "grain" lines/blotches
for _ in range(50):
    x = np.random.randint(0, width)
    y = np.random.randint(0, height)
    r = np.random.randint(5, 50)
    # Simple blotch logic via array slicing would be complex, 
    # relying on the noise is sufficient for "paper texture" checks

img = Image.fromarray(texture)
img.save("/home/ga/OpenToonz/inputs/parchment_texture.jpg", quality=95)
EOF

python3 /tmp/gen_texture.py
chown ga:ga /home/ga/OpenToonz/inputs/parchment_texture.jpg
echo "Texture created at /home/ga/OpenToonz/inputs/parchment_texture.jpg"

# Ensure OpenToonz is running
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    sleep 15
fi

# Focus and maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="