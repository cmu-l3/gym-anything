#!/bin/bash
set -e

echo "=== Setting up draw line task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq python3-pil python3-numpy python3-scipy python3-scikit-learn imagemagick

# Create a light-colored canvas for drawing
echo "🎨 Creating blank canvas for line drawing..."
cd /home/ga/Desktop/
convert -size 600x400 xc:white blank_canvas.png

# Set proper permissions
chown ga:ga blank_canvas.png
chmod 644 blank_canvas.png

echo "✅ Blank canvas created at /home/ga/Desktop/blank_canvas.png"

echo "🎨 Opening GIMP with the blank canvas..."
# Launch GIMP with the blank canvas
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/blank_canvas.png > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Draw line task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The blank canvas is already open in GIMP"
echo "   2. Select the Pencil Tool (N key or from toolbox)"
echo "   3. Set foreground color to bright red (RGB: 255, 0, 0)"
echo "   4. Click at one point on the canvas"
echo "   5. Hold Shift and click at another point to draw a straight line"
echo "   6. Make sure the line is clearly visible and reasonably long"
echo "   7. The export will be automated after drawing"