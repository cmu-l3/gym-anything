#!/bin/bash
set -e

echo "=== Setting up paintbrush drawing task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq imagemagick python3-pil python3-numpy python3-scipy

# Create a blank white canvas for drawing
echo "🎨 Creating blank canvas..."
cd /home/ga/Desktop/
convert -size 800x600 xc:white blank_canvas.png || {
    echo "❌ ImageMagick failed, creating simple canvas with Python..."
    python3 -c "
from PIL import Image
img = Image.new('RGB', (800, 600), 'white')
img.save('/home/ga/Desktop/blank_canvas.png')
"
}

# Set proper permissions
chown ga:ga blank_canvas.png
chmod 644 blank_canvas.png

echo "✅ Blank canvas created at /home/ga/Desktop/blank_canvas.png"

echo "🎨 Opening GIMP with the blank canvas..."
# Launch GIMP with the blank canvas
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/blank_canvas.png > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Paintbrush drawing task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The blank canvas is already open in GIMP"
echo "   2. Select the Paintbrush Tool (P key or from toolbox)"
echo "   3. Choose an appropriate brush size (20-30 pixels recommended)"
echo "   4. Select a contrasting color (e.g., black on white canvas)"
echo "   5. Draw several distinct brush strokes on the canvas"
echo "   6. Create at least 3-5 separate stroke elements"
echo "   7. Vary stroke lengths and directions to show tool control"
echo "   8. The export will be automated after drawing"