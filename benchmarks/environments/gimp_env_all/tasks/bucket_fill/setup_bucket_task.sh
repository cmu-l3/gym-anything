#!/bin/bash
set -e

echo "=== Setting up bucket fill task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download line art image with clear bounded areas for bucket filling
echo "📥 Downloading line art image..."
cd /home/ga/Desktop/
wget -q -O line_art.jpg "https://images.unsplash.com/photo-1513475382585-d06e58bcb0e0?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O line_art.jpg "https://images.unsplash.com/photo-1578662996442-48f60103fc96?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple line art with bounded regions if download fails
        convert -size 600x400 xc:white -fill none -stroke black -strokewidth 3 \
                -draw "rectangle 50,50 250,200" \
                -draw "circle 400,150 500,150" \
                -draw "rectangle 100,250 350,350" \
                -fill black -pointsize 16 -gravity center -annotate +0-150 "FILL THE SHAPES WITH RED" \
                line_art.jpg
    }
}

# Set proper permissions
chown ga:ga line_art.jpg
chmod 644 line_art.jpg

echo "✅ Line art image downloaded to /home/ga/Desktop/line_art.jpg"

echo "🎨 Opening GIMP with the line art image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/line_art.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Bucket fill task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The line art image is already open in GIMP"
echo "   2. Select the Bucket Fill tool (Shift+B or from toolbox)"
echo "   3. Click on the foreground color square to open color picker"
echo "   4. Select bright red color (#FF0000 or similar)"
echo "   5. Click OK to confirm color selection"
echo "   6. Click inside a bounded area (like a rectangle or circle) to fill it"
echo "   7. Verify the area fills completely with red color"
echo "   8. The export will be automated after editing"