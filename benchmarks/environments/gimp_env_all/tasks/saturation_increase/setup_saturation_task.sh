#!/bin/bash
set -e

echo "=== Setting up saturation increase task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download colorful landscape image suitable for saturation enhancement
echo "📥 Downloading colorful landscape image..."
cd /home/ga/Desktop/
wget -q -O colorful_landscape.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O colorful_landscape.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with various colors if download fails
        convert -size 800x600 xc:white -fill red -draw "rectangle 50,50 200,200" -fill green -draw "rectangle 250,50 400,200" -fill blue -draw "rectangle 450,50 600,200" -fill orange -draw "rectangle 50,250 200,400" -fill purple -draw "rectangle 250,250 400,400" -fill cyan -draw "rectangle 450,250 600,400" colorful_landscape.jpg
    }
}

# Set proper permissions
chown ga:ga colorful_landscape.jpg
chmod 644 colorful_landscape.jpg

echo "✅ Colorful landscape image downloaded to /home/ga/Desktop/colorful_landscape.jpg"

echo "🎨 Opening GIMP with the colorful landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/colorful_landscape.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Saturation increase task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The colorful landscape image is already open in GIMP"
echo "   2. Go to Colors → Hue-Saturation"
echo "   3. In the Hue-Saturation dialog:"
echo "      - Make sure 'Master' channel is selected"
echo "      - Increase the Saturation slider (try +25 to +35)"
echo "      - Watch the preview to see colors become more vibrant"
echo "   4. Click OK to apply the saturation increase"
echo "   5. The export will be automated after editing"