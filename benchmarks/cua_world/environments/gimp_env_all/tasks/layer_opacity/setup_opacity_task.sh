#!/bin/bash
set -e

echo "=== Setting up layer opacity task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a beautiful flower image for opacity adjustment
echo "📥 Downloading flower image..."
cd /home/ga/Desktop/
wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1490750967868-88aa4486c946?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1518709268805-4e9042af2176?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 600x400 xc:lightblue -fill yellow -draw "circle 300,200 350,250" -fill black -pointsize 24 -gravity center -annotate +0+50 "SET OPACITY TO 65%" flower_image.jpg
    }
}

# Set proper permissions
chown ga:ga flower_image.jpg
chmod 644 flower_image.jpg

echo "✅ Flower image downloaded to /home/ga/Desktop/flower_image.jpg"

echo "🎨 Opening GIMP with the flower image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flower_image.jpg > /tmp/gimp_opacity.log 2>&1 &"

sleep 3

echo "=== Layer opacity task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The flower image is already open in GIMP"
echo "   2. Locate the Layers panel (usually on the right side)"
echo "   3. If Layers panel is not visible, go to Windows → Dockable Dialogs → Layers"
echo "   4. Find the opacity slider/input in the layers panel"
echo "   5. Change the opacity from 100% to exactly 65%"
echo "   6. You can either:"
echo "      - Drag the opacity slider to 65%"
echo "      - Click in the opacity field and type '65'"
echo "   7. Verify the image becomes semi-transparent"
echo "   8. The export will be automated after editing"