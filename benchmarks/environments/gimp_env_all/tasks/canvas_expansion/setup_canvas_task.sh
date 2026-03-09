#!/bin/bash
set -e

echo "=== Setting up canvas expansion task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a suitable image for canvas expansion
echo "📥 Downloading sample image..."
cd /home/ga/Desktop/
wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1506744038136-46273834b3fb?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=600&h=400&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&h=400&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 400x300 xc:lightblue -fill darkblue -draw "rectangle 100,75 300,225" -fill white -pointsize 24 -gravity center -annotate +0+0 "EXPAND CANVAS" sample_image.jpg
    }
}

# Set proper permissions
chown ga:ga sample_image.jpg
chmod 644 sample_image.jpg

echo "✅ Sample image downloaded to /home/ga/Desktop/sample_image.jpg"

echo "🎨 Opening GIMP with the sample image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/sample_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Canvas expansion task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The sample image is already open in GIMP"
echo "   2. Go to Image → Canvas Size"
echo "   3. Add 100 pixels to both width and height"
echo "   4. Ensure the image remains centered (default behavior)"
echo "   5. Click 'Resize' to apply the canvas expansion"
echo "   6. The export will be automated after editing"