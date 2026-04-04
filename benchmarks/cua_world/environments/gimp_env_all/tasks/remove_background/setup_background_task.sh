#!/bin/bash
set -e

echo "=== Setting up background removal task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with clear subject on white background
echo "📥 Downloading product image on white background..."
cd /home/ga/Desktop/
wget -q -O product_image.jpg "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O product_image.jpg "https://images.unsplash.com/photo-1542291026-7eec264c27ff?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, creating fallback image..."
        # Create a simple test image with clear subject on white background
        convert -size 800x600 xc:white \
                -fill "#FF6B35" -draw "circle 400,300 200,400" \
                -fill black -pointsize 24 -gravity center \
                -annotate +0+150 "REMOVE WHITE BACKGROUND" \
                product_image.jpg || {
            # Ultimate fallback if ImageMagick not available
            python3 -c "
from PIL import Image, ImageDraw, ImageFont
import os
img = Image.new('RGB', (800, 600), 'white')
draw = ImageDraw.Draw(img)
draw.ellipse([200, 150, 600, 450], fill='#FF6B35')
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 20)
except:
    font = ImageFont.load_default()
draw.text((400, 500), 'REMOVE WHITE BACKGROUND', fill='black', anchor='mm', font=font)
img.save('product_image.jpg')
print('Created fallback test image')
"
        }
    }
}

# Set proper permissions
chown ga:ga product_image.jpg
chmod 644 product_image.jpg

echo "✅ Product image downloaded to /home/ga/Desktop/product_image.jpg"

echo "🎨 Opening GIMP with the product image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/product_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Background removal task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The product image is already open in GIMP"
echo "   2. Go to Layer → Transparency → Add Alpha Channel"
echo "   3. Select the 'Select by Color Tool' (Shift+O or from toolbox)"
echo "   4. Click on the white background to select it"
echo "   5. Adjust threshold if needed to select all white areas"
echo "   6. Press Delete key to remove the selected background"
echo "   7. Go to Select → None to deselect"
echo "   8. The export will be automated as PNG with transparency"