#!/bin/bash
set -e

echo "=== Setting up selection stroke task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with a clear flower subject
echo "📥 Downloading flower image..."
cd /home/ga/Desktop/
wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1578662996442-48f60103fc96?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with a central flower-like shape if download fails
        convert -size 600x400 xc:lightgreen -fill yellow -draw "circle 300,200 350,250" -fill black -pointsize 24 -gravity center -annotate +0+150 "STROKE ME" flower_image.jpg
    }
}

# Set proper permissions
chown ga:ga flower_image.jpg
chmod 644 flower_image.jpg

echo "✅ Flower image downloaded to /home/ga/Desktop/flower_image.jpg"

echo "🎨 Opening GIMP with the flower image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flower_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Selection stroke task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The flower image is already open in GIMP"
echo "   2. Select the Ellipse Select Tool (E key or from toolbox)"
echo "   3. Create an elliptical selection around the central flower"
echo "   4. Go to Edit → Stroke Selection"
echo "   5. Set stroke width to 8 pixels"
echo "   6. Set stroke color to bright red (#FF0000)"
echo "   7. Click 'Stroke' to apply the red outline"
echo "   8. Go to Select → None to clear the selection"
echo "   9. The export will be automated after editing"