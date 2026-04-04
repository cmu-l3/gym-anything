#!/bin/bash
set -e

echo "=== Setting up percentage scaling task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with clear dimensions for scaling verification
echo "📥 Downloading test image for scaling..."
cd /home/ga/Desktop/
wget -q -O test_scale_image.jpg "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&h=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O test_scale_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightblue -fill darkblue -draw "rectangle 100,100 700,500" -fill white -pointsize 48 -gravity center -annotate +0+0 "SCALE TO 50%" test_scale_image.jpg
    }
}

# Set proper permissions
chown ga:ga test_scale_image.jpg
chmod 644 test_scale_image.jpg

echo "✅ Test image downloaded to /home/ga/Desktop/test_scale_image.jpg"

echo "🎨 Opening GIMP with the test image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/test_scale_image.jpg > /tmp/gimp_scale_task.log 2>&1 &"

sleep 3

echo "=== Percentage scaling task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The test image is already open in GIMP"
echo "   2. Go to Image → Scale Image"
echo "   3. Change the units to % (percent) if available, OR:"
echo "   4. Calculate 50% of current dimensions and enter pixel values"
echo "   5. Ensure the chain link is connected to maintain aspect ratio"
echo "   6. Set both width and height to 50% of original"
echo "   7. Click Scale to apply the resize"
echo "   8. The export will be automated after scaling"