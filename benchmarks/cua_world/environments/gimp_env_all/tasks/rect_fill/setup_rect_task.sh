#!/bin/bash
set -e

echo "=== Setting up rectangle selection and fill task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a landscape image suitable for rectangle overlay
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightgray -fill black -pointsize 24 -gravity center -annotate +0+0 "ADD BLUE RECTANGLE" landscape_image.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_image.jpg
chmod 644 landscape_image.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_image.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_image.jpg > /tmp/gimp_rect_task.log 2>&1 &"

sleep 3

echo "=== Rectangle fill task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Select the Rectangle Select Tool (R key or from toolbox)"
echo "   3. Click and drag to create a rectangle selection in the center area"
echo "   4. Set the foreground color to blue (#0000FF or RGB: 0, 0, 255)"
echo "   5. Fill the selection with Edit → Fill with Foreground Color"
echo "   6. Deselect with Select → None (Ctrl+Shift+A)"
echo "   7. The export will be automated after editing"