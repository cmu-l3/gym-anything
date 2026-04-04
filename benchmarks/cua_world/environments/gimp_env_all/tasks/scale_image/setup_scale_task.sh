#!/bin/bash
set -e

echo "=== Setting up scale image task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image that needs scaling (not already 600x400)
echo "📥 Downloading sample image for scaling..."
cd /home/ga/Desktop/
wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&h=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightblue -fill darkblue -pointsize 36 -gravity center -annotate +0+0 "SCALE ME TO 600x400" sample_image.jpg
    }
}

# Set proper permissions
chown ga:ga sample_image.jpg
chmod 644 sample_image.jpg

echo "✅ Sample image downloaded to /home/ga/Desktop/sample_image.jpg"

echo "🎨 Opening GIMP with the sample image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/sample_image.jpg > /tmp/gimp_scale.log 2>&1 &"

sleep 3

echo "=== Scale image task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The sample image is already open in GIMP"
echo "   2. Go to Image → Scale Image in the menu bar"
echo "   3. In the Scale Image dialog:"
echo "      - Set width to 600 pixels"
echo "      - Set height to 400 pixels" 
echo "      - Break the chain link if needed for exact dimensions"
echo "   4. Click Scale to apply the resize"
echo "   5. The export will be automated after scaling"