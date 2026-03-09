#!/bin/bash
set -e

echo "=== Setting up border addition task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download portrait image for border addition
echo "📥 Downloading portrait image..."
cd /home/ga/Desktop/
wget -q -O portrait_image.jpg "https://images.unsplash.com/photo-1494790108755-2616b612b691?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O portrait_image.jpg "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?ixlib=rb-4.0.3&auto=format&fit=crop&w=700&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 300x400 xc:lightgray -fill darkblue -draw "rectangle 50,50 250,350" -fill white -pointsize 24 -gravity center -annotate +0+0 "ADD BORDER" portrait_image.jpg
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

echo "=== Border addition task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait image is already open in GIMP"
echo "   2. Go to Image → Canvas Size"
echo "   3. Add 40 pixels to both width and height (20px border on all sides)"
echo "   4. Make sure the anchor is centered so image stays in middle"
echo "   5. Click Resize to expand the canvas"
echo "   6. Set foreground color to white"
echo "   7. Use Bucket Fill tool to fill the transparent border areas"
echo "   8. Fill all four border regions around the original image"
echo "   9. The export will be automated after editing"