#!/bin/bash
set -e

echo "=== Setting up round corners task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with clear rectangular shape for rounded corners
echo "📥 Downloading rectangular image..."
cd /home/ga/Desktop/
wget -q -O corner_image.jpg "https://images.unsplash.com/photo-1557804506-669a67965ba0?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O corner_image.jpg "https://images.unsplash.com/photo-1486312338219-ce68d2c6f44d?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear corners if download fails
        convert -size 600x400 xc:lightblue -fill darkblue -draw "rectangle 50,50 550,350" -fill white -pointsize 24 -gravity center -annotate +0+0 "ROUND MY CORNERS" corner_image.jpg
    }
}

# Set proper permissions
chown ga:ga corner_image.jpg
chmod 644 corner_image.jpg

echo "✅ Image downloaded to /home/ga/Desktop/corner_image.jpg"

echo "🎨 Opening GIMP with the corner image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/corner_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Round corners task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The rectangular image is already open in GIMP"
echo "   2. Go to Layer → Transparency → Add Alpha Channel (if needed)"
echo "   3. Navigate to Filters → Decor → Round Corners"
echo "   4. Set Edge radius to 30 pixels"
echo "   5. Uncheck 'Add drop shadow' if checked"
echo "   6. Uncheck 'Add background layer' if checked"
echo "   7. Click OK to apply the rounded corners effect"
echo "   8. The export will be automated after editing"