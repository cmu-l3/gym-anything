#!/bin/bash
set -e

echo "=== Setting up ellipse fill task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy imagemagick

# Create a simple blank canvas image for the task
echo "🎨 Creating blank canvas image..."
cd /home/ga/Desktop/
convert -size 600x400 xc:white -fill lightgray -stroke gray -strokewidth 1 -draw "rectangle 5,5 594,394" blank_canvas.jpg

# Alternative: Download a simple textured background if convert fails
if [ ! -f "blank_canvas.jpg" ]; then
    echo "📥 Downloading simple background image..."
    wget -q -O blank_canvas.jpg "https://images.unsplash.com/photo-1557683316-973673baf926?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&h=400&q=80" || {
        echo "❌ Failed to download, creating basic white image..."
        # Create a simple white image with Python if ImageMagick fails
        python3 -c "
from PIL import Image
img = Image.new('RGB', (600, 400), 'white')
img.save('blank_canvas.jpg')
"
    }
fi

# Set proper permissions
chown ga:ga blank_canvas.jpg
chmod 644 blank_canvas.jpg

echo "✅ Blank canvas created at /home/ga/Desktop/blank_canvas.jpg"

echo "🎨 Opening GIMP with the blank canvas..."
# Launch GIMP with the canvas image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/blank_canvas.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Ellipse fill task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The blank canvas is already open in GIMP"
echo "   2. Set foreground color to red (255, 0, 0)"
echo "   3. Select the Ellipse Select Tool (E key or from toolbox)"
echo "   4. Create a circular selection in the center area"
echo "   5. Use the Bucket Fill tool (Shift+B) to fill the selection with red"
echo "   6. Go to Select → None to clear the selection"
echo "   7. The export will be automated after editing"