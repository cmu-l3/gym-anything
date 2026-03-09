#!/bin/bash
set -e

echo "=== Setting up checkerboard pattern task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq python3-pil python3-numpy python3-scipy python3-scikit-learn

# Create a blank white canvas for pattern generation
echo "📄 Creating blank canvas for checkerboard pattern..."
cd /home/ga/Desktop/
convert -size 400x400 xc:white blank_canvas.png

# Set proper permissions
chown ga:ga blank_canvas.png
chmod 644 blank_canvas.png

echo "✅ Blank canvas created at /home/ga/Desktop/blank_canvas.png"

echo "🎨 Opening GIMP with the blank canvas..."
# Launch GIMP with the blank canvas
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/blank_canvas.png > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Checkerboard pattern task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The blank canvas is already open in GIMP"
echo "   2. Go to Filters → Render → Pattern → Checkerboard"
echo "   3. In the checkerboard dialog:"
echo "      - Set an appropriate check size (e.g., 20-30 pixels)"
echo "      - Keep default colors (black/white) or use high contrast colors"
echo "   4. Click OK to apply the checkerboard pattern"
echo "   5. The export will be automated after pattern generation"