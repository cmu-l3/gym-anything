#!/bin/bash
set -e

echo "=== Setting up posterize effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a colorful image that will show posterize effect well
echo "📥 Downloading colorful landscape image..."
cd /home/ga/Desktop/
wget -q -O colorful_photo.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O colorful_photo.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with smooth gradations if download fails
        convert -size 800x600 gradient:blue-red -swirl 60 colorful_photo.jpg
    }
}

# Set proper permissions
chown ga:ga colorful_photo.jpg
chmod 644 colorful_photo.jpg

echo "✅ Colorful image downloaded to /home/ga/Desktop/colorful_photo.jpg"

echo "🎨 Opening GIMP with the colorful image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/colorful_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Posterize task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The colorful image is already open in GIMP"
echo "   2. Go to Colors → Posterize in the menu"
echo "   3. In the Posterize dialog:"
echo "      - Set the posterize levels to 4"
echo "      - Observe the preview showing distinct color bands"
echo "      - Click OK to apply the effect"
echo "   4. The export will be automated after editing"