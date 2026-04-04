#!/bin/bash
set -e

echo "=== Setting up paste as new layer task ==="

# Install required packages for verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download an image with clear, distinct regions suitable for selection
echo "📥 Downloading composite image..."
cd /home/ga/Desktop/
wget -q -O composite_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O composite_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with distinct regions if download fails
        convert -size 800x600 xc:lightblue -fill darkgreen -draw "rectangle 200,150 600,450" -fill red -draw "circle 400,300 500,300" -fill black -pointsize 24 -gravity center -annotate +0+200 "SELECT AND COPY ME" composite_image.jpg
    }
}

# Set proper permissions
chown ga:ga composite_image.jpg
chmod 644 composite_image.jpg

echo "✅ Composite image downloaded to /home/ga/Desktop/composite_image.jpg"

echo "🎨 Opening GIMP with the composite image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/composite_image.jpg > /tmp/gimp_paste.log 2>&1 &"

sleep 3

echo "=== Paste as new layer task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The composite image is already open in GIMP"
echo "   2. Select the Rectangle Select Tool (R key or from toolbox)"
echo "   3. Click and drag to select a region (e.g., central area with 30-50% of image)"
echo "   4. Copy the selection using Edit → Copy (or Ctrl+C)"
echo "   5. Paste as new layer using Edit → Paste as → New Layer"
echo "   6. Verify a new layer appears in the layers dialog"
echo "   7. The export will be automated after editing"