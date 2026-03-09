#!/bin/bash
set -e

echo "=== Setting up partial erasure task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image suitable for erasure (solid background, clear subject)
echo "📥 Downloading test image..."
cd /home/ga/Desktop/
wget -q -O test_image.jpg "https://images.unsplash.com/photo-1441986300917-64674bd600d8?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O test_image.jpg "https://images.unsplash.com/photo-1574169208507-84376144848b?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightblue -fill darkblue -draw "circle 400,300 400,200" -fill white -pointsize 24 -gravity center -annotate +0+0 "ERASE CENTER" test_image.jpg
    }
}

# Set proper permissions
chown ga:ga test_image.jpg
chmod 644 test_image.jpg

echo "✅ Test image downloaded to /home/ga/Desktop/test_image.jpg"

echo "🎨 Opening GIMP with the test image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/test_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Partial erasure task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The test image is already open in GIMP"
echo "   2. First, add alpha channel: Layer → Transparency → Add Alpha Channel"
echo "   3. Select the Eraser tool (Shift+E or from toolbox)"
echo "   4. Adjust eraser size if needed (larger brush recommended)"
echo "   5. Erase the center region of the image to create transparency"
echo "   6. You should see checkerboard pattern indicating transparency"
echo "   7. The export will be automated after editing (must be PNG format)"