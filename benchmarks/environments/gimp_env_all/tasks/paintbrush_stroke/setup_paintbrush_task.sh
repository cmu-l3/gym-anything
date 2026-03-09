#!/bin/bash
set -e

echo "=== Setting up paintbrush stroke task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a suitable photograph for painting on
echo "📥 Downloading photograph for painting..."
cd /home/ga/Desktop/
wget -q -O photo_canvas.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_canvas.jpg "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightgray -fill darkgray -draw "rectangle 100,100 700,500" -fill black -pointsize 32 -gravity center -annotate +0+0 "PAINT ON ME" photo_canvas.jpg
    }
}

# Set proper permissions
chown ga:ga photo_canvas.jpg
chmod 644 photo_canvas.jpg

echo "✅ Photo canvas downloaded to /home/ga/Desktop/photo_canvas.jpg"

echo "🎨 Opening GIMP with the photo canvas..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_canvas.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Paintbrush stroke task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photo canvas is already open in GIMP"
echo "   2. Select the Paintbrush tool (P key or from toolbox)"
echo "   3. Choose a bright, contrasting color (red, yellow, cyan, etc.)"
echo "   4. Optionally adjust brush size if needed (40-80 pixels recommended)"
echo "   5. Click and drag on the canvas to paint a visible stroke"
echo "   6. Make sure the stroke is clearly visible and substantial"
echo "   7. The export will be automated after painting"