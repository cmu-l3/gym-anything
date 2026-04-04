#!/bin/bash
set -e

echo "=== Setting up clone duplication task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-opencv-python || {
    echo "Installing opencv-python via pip as fallback..."
    pip3 install opencv-python
}

# Download image with distinct elements suitable for cloning
echo "📥 Downloading garden scene with flowers..."
cd /home/ga/Desktop/
wget -q -O clone_scene.jpg "https://images.unsplash.com/photo-1416879595882-3373a0480b5b?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O clone_scene.jpg "https://images.unsplash.com/photo-1558618047-3c8c76ca7d13?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with distinct elements if download fails
        convert -size 800x600 xc:lightgreen \
                -fill red -draw "circle 200,200 200,250" \
                -fill blue -draw "circle 600,400 600,450" \
                -fill yellow -draw "rectangle 100,400 200,500" \
                -fill black -pointsize 24 -gravity center \
                -annotate +0-200 "Clone the red circle" clone_scene.jpg
    }
}

# Set proper permissions
chown ga:ga clone_scene.jpg
chmod 644 clone_scene.jpg

echo "✅ Clone scene image downloaded to /home/ga/Desktop/clone_scene.jpg"

echo "🎨 Opening GIMP with the clone scene..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/clone_scene.jpg > /tmp/gimp_clone.log 2>&1 &"

sleep 3

echo "=== Clone duplication task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The garden/scene image is already open in GIMP"
echo "   2. Select the Clone Tool (C key or from toolbox)"
echo "   3. Choose an interesting element to duplicate (flower, object, etc.)"
echo "   4. Hold Ctrl and click on the element to set clone source"
echo "   5. Move to a different area and paint to clone the element"
echo "   6. Apply enough coverage to create a recognizable duplicate"
echo "   7. The export will be automated after editing"