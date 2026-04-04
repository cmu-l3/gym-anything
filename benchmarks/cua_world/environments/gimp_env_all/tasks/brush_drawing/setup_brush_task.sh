#!/bin/bash
set -e

echo "=== Setting up brush drawing task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq imagemagick python3-pil python3-numpy python3-scipy

# Create a blank canvas with subtle texture for brush work
echo "🎨 Creating blank canvas for painting..."
cd /home/ga/Desktop/
convert -size 800x600 xc:white -noise 0.02 -blur 0x0.5 -fill 'rgb(248,248,248)' -draw 'color 0,0 paint' blank_canvas.jpg

# Set proper permissions
chown ga:ga blank_canvas.jpg
chmod 644 blank_canvas.jpg

echo "✅ Blank canvas created at /home/ga/Desktop/blank_canvas.jpg"

echo "🎨 Opening GIMP with the blank canvas..."
# Launch GIMP with the canvas
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/blank_canvas.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Brush drawing task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The blank canvas is already open in GIMP"
echo "   2. Select the Brush Tool (P key or from toolbox)"
echo "   3. Choose an appropriate brush size (20-50 pixels recommended)"
echo "   4. Select a contrasting color (e.g., red, blue, black)"
echo "   5. Paint several visible brush strokes on the canvas"
echo "   6. Create at least 2-3 distinct strokes in different areas"
echo "   7. Ensure strokes are visible and substantial"
echo "   8. The export will be automated after painting"