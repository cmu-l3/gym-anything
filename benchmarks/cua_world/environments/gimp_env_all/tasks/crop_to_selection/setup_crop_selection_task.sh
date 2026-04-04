#!/bin/bash
set -e

echo "=== Setting up crop to selection task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with clear subject and extraneous background for cropping
echo "📥 Downloading image suitable for cropping..."
cd /home/ga/Desktop/
wget -q -O wide_landscape.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O wide_landscape.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with clear subject and borders if download fails
        convert -size 1000x600 xc:lightblue -fill darkgreen -draw "rectangle 300,150 700,450" -fill yellow -draw "circle 500,300 550,350" -fill black -pointsize 24 -gravity center -annotate +0+0 "CROP THIS SUBJECT" wide_landscape.jpg
    }
}

# Set proper permissions
chown ga:ga wide_landscape.jpg
chmod 644 wide_landscape.jpg

echo "✅ Wide landscape image downloaded to /home/ga/Desktop/wide_landscape.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/wide_landscape.jpg > /tmp/gimp_crop_selection.log 2>&1 &"

sleep 3

echo "=== Crop to selection task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The wide landscape image is already open in GIMP"
echo "   2. Select the Rectangle Select Tool (R key or from toolbox)"
echo "   3. Click and drag to create a rectangular selection around the main subject"
echo "   4. Adjust the selection boundaries if needed"
echo "   5. Go to Image → Crop to Selection"
echo "   6. The image should now be cropped to your selection"
echo "   7. The export will be automated after editing"