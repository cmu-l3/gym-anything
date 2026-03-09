#!/bin/bash
set -e

echo "=== Setting up solid noise render task ==="

# Install required packages for image processing and verification
apt-get update -qq
apt-get install -y -qq python3-pil python3-numpy python3-scipy imagemagick

# Create a blank canvas for noise generation
echo "🖼️ Creating blank canvas..."
cd /home/ga/Desktop/
convert -size 512x512 xc:white blank_canvas.png || {
    echo "❌ Failed to create canvas with ImageMagick, trying alternative..."
    # Fallback: create a simple solid color image using Python
    python3 -c "
from PIL import Image
img = Image.new('RGB', (512, 512), color=(255, 255, 255))
img.save('/home/ga/Desktop/blank_canvas.png')
print('✅ Created blank canvas using Python')
"
}

# Set proper permissions
chown ga:ga blank_canvas.png
chmod 644 blank_canvas.png

echo "✅ Blank canvas created at /home/ga/Desktop/blank_canvas.png"

echo "🎨 Opening GIMP with the blank canvas..."
# Launch GIMP with the blank canvas
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/blank_canvas.png > /tmp/gimp_noise.log 2>&1 &"

sleep 3

echo "=== Solid noise task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The blank canvas is already open in GIMP"
echo "   2. Go to Filters → Render → Clouds → Solid Noise"
echo "   3. Optionally adjust parameters:"
echo "      - Turbulence: controls noise smoothness (1-7)"
echo "      - Detail: controls noise complexity (1-15)" 
echo "   4. Click OK to generate the noise texture"
echo "   5. The export will be automated after rendering"