#!/bin/bash
echo "=== Setting up Visual Ad Testing Survey Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create dummy concept images
echo "Generating concept images..."
mkdir -p /home/ga/Documents/Concepts

# Check if ImageMagick is installed, otherwise use python to generate simple images
if command -v convert >/dev/null 2>&1; then
    # Concept 1: Vibrant
    convert -size 600x400 xc:red -gravity Center -pointsize 30 -fill white \
        -annotate 0 "VIBRANT DESIGN\nCONCEPT A" \
        /home/ga/Documents/Concepts/concept_vibrant.png
    
    # Concept 2: Minimalist
    convert -size 600x400 xc:white -bordercolor black -border 5 -gravity Center \
        -pointsize 30 -fill black \
        -annotate 0 "MINIMALIST DESIGN\nCONCEPT B" \
        /home/ga/Documents/Concepts/concept_minimalist.png
else
    # Fallback python generation if convert missing
    python3 -c "
from PIL import Image, ImageDraw
img1 = Image.new('RGB', (600, 400), color = 'red')
d1 = ImageDraw.Draw(img1)
d1.text((200,200), 'VIBRANT A', fill=(255,255,255))
img1.save('/home/ga/Documents/Concepts/concept_vibrant.png')

img2 = Image.new('RGB', (600, 400), color = 'white')
d2 = ImageDraw.Draw(img2)
d2.rectangle([0,0,599,399], outline='black', width=5)
d2.text((200,200), 'MINIMALIST B', fill=(0,0,0))
img2.save('/home/ga/Documents/Concepts/concept_minimalist.png')
"
fi

# Set permissions so agent can access
chown -R ga:ga /home/ga/Documents/Concepts
chmod 644 /home/ga/Documents/Concepts/*.png

# Ensure Firefox is ready
focus_firefox

# Navigate to admin home
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Images created at /home/ga/Documents/Concepts/"