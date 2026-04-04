#!/bin/bash
set -e

echo "=== Setting up circle fill task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a neutral background image suitable for drawing shapes
echo "📥 Downloading background image..."
cd /home/ga/Desktop/
wget -q -O background_image.jpg "https://images.unsplash.com/photo-1557682224-5b8590cd9ec5?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&h=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O background_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple light background if download fails
        convert -size 800x600 xc:"#f0f0f0" -pointsize 24 -gravity center -fill gray -annotate +0+0 "DRAW CIRCLE HERE" background_image.jpg
    }
}

# Set proper permissions
chown ga:ga background_image.jpg
chmod 644 background_image.jpg

echo "✅ Background image downloaded to /home/ga/Desktop/background_image.jpg"

echo "🎨 Opening GIMP with the background image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/background_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Circle fill task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The background image is already open in GIMP"
echo "   2. Select the Ellipse Select Tool (E key or from toolbox)"
echo "   3. Create a circular selection in the center of the image"
echo "   4. Set foreground color to red (#FF0000)"
echo "   5. Fill the selection with Edit → Fill with FG Color (or Ctrl+;)"
echo "   6. Deselect with Select → None (or Ctrl+Shift+A)"
echo "   7. The export will be automated after editing"