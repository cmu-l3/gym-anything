#!/bin/bash
set -e

echo "=== Setting up crop and resize task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with a clear subject to crop
echo "📥 Downloading portrait image..."
cd /home/ga/Desktop/
wget -q -O portrait_image.jpg "https://images.unsplash.com/photo-1531123897727-8f129e1688ce?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O portrait_image.jpg "https://images.unsplash.com/photo-1544005313-94ddf0286df2?ixlib=rb-4.0.3&auto=format&fit=crop&w=688&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightblue -fill black -pointsize 48 -gravity center -annotate +0+0 "CROP ME" portrait_image.jpg
    }
}

# Set proper permissions
chown ga:ga portrait_image.jpg
chmod 644 portrait_image.jpg

echo "✅ Portrait image downloaded to /home/ga/Desktop/portrait_image.jpg"

echo "🎨 Opening GIMP with the portrait image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/portrait_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Crop and resize task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait image is already open in GIMP"
echo "   2. Use the Crop Tool (Shift+C or from toolbox)"
echo "   3. Select around the main subject (person's face/torso area)"
echo "   4. Apply the crop by pressing Enter or clicking inside the selection"
echo "   5. Go to Image → Scale Image"
echo "   6. Set width to 400 and height to 300 pixels"
echo "   7. Click Scale to apply the resize"
echo "   8. The export will be automated after editing"
