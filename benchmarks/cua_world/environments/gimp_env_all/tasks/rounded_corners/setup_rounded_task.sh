#!/bin/bash
set -e

echo "=== Setting up rounded corners task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download rectangular image suitable for rounded corners
echo "📥 Downloading rectangular image..."
cd /home/ga/Desktop/
wget -q -O rectangle_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&h=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O rectangle_image.jpg "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple rectangular test image if download fails
        convert -size 600x400 xc:skyblue -fill white -stroke black -strokewidth 2 -draw "rectangle 50,50 550,350" -fill black -pointsize 24 -gravity center -annotate +0+0 "ADD ROUNDED CORNERS" rectangle_image.jpg
    }
}

# Set proper permissions
chown ga:ga rectangle_image.jpg
chmod 644 rectangle_image.jpg

echo "✅ Rectangular image downloaded to /home/ga/Desktop/rectangle_image.jpg"

echo "🎨 Opening GIMP with the rectangular image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/rectangle_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Rounded corners task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The rectangular image is already open in GIMP"
echo "   2. Go to Filters → Decor → Round Corners"
echo "   3. Set an appropriate corner radius (20-40 pixels recommended)"
echo "   4. Make sure 'Add drop shadow' is unchecked if present"
echo "   5. Click OK to apply the rounded corners effect"
echo "   6. The corners will become transparent (checkerboard pattern)"
echo "   7. The export will be automated as PNG to preserve transparency"