#!/bin/bash
echo "=== Setting up QA Screencast Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos/qa_reports/
mkdir -p /home/ga/Pictures/

# Generate the "Bug Reference" image template
# Using a distinct geometric pattern so OpenCV template matching is extremely reliable
cat > /tmp/make_bug_img.py << 'EOF'
from PIL import Image, ImageDraw, ImageFont

# Create a 400x300 image (small enough that viewers won't downscale it by default)
img = Image.new('RGB', (400, 300), color=(40, 44, 52))
d = ImageDraw.Draw(img)

# Draw a distinct bounding box (Red)
d.rectangle([20, 20, 380, 280], fill=(220, 50, 50), outline=(255, 255, 255), width=4)

# Draw an inner geometric pattern (White cross)
d.line([20, 20, 380, 280], fill=(255, 255, 255), width=8)
d.line([20, 280, 380, 20], fill=(255, 255, 255), width=8)

# Draw a center circle (Blue)
d.ellipse([150, 100, 250, 200], fill=(50, 100, 220), outline=(255, 255, 255), width=4)

img.save('/home/ga/Pictures/bug_reference_ui.png')
EOF

python3 /tmp/make_bug_img.py
chown -R ga:ga /home/ga/Pictures/ /home/ga/Videos/

# Ensure VLC is NOT running initially
kill_vlc "ga"

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="