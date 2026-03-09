#!/bin/bash
set -e

echo "=== Setting up pixelate effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with fine details suitable for pixelation
echo "📥 Downloading detailed image..."
cd /home/ga/Desktop/
wget -q -O detailed_image.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O detailed_image.jpg "https://images.unsplash.com/photo-1544005313-94ddf0286df2?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a detailed test image if download fails
        convert -size 800x600 xc:white \
                -fill red -draw "rectangle 100,100 200,200" \
                -fill blue -draw "rectangle 300,200 400,300" \
                -fill green -draw "rectangle 500,300 600,400" \
                -fill black -pointsize 24 -gravity center -annotate +0+0 "DETAILED IMAGE" \
                detailed_image.jpg
    }
}

# Set proper permissions
chown ga:ga detailed_image.jpg
chmod 644 detailed_image.jpg

echo "✅ Detailed image downloaded to /home/ga/Desktop/detailed_image.jpg"

echo "🎨 Opening GIMP with the detailed image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/detailed_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Pixelate effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The detailed image is already open in GIMP"
echo "   2. Go to Filters → Blur → Pixelize (or similar filter)"
echo "   3. In the Pixelize dialog:"
echo "      - Set pixel width/block size to create visible pixelation (try 10-20)"
echo "      - Check the preview to ensure effect is visible"
echo "   4. Click OK to apply the pixelate filter"
echo "   5. Verify the image has a mosaic/blocky appearance"
echo "   6. The export will be automated after editing"