#!/bin/bash
set -e

echo "=== Setting up pixelate filter task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with fine details that will show pixelation clearly
echo "📥 Downloading detailed portrait image..."
cd /home/ga/Desktop/
wget -q -O detailed_portrait.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O detailed_portrait.jpg "https://images.unsplash.com/photo-1534528741775-53994a69daeb?ixlib=rb-4.0.3&auto=format&fit=crop&w=700&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a detailed test image if download fails
        convert -size 800x600 xc:white \
                -fill red -draw "rectangle 100,100 300,300" \
                -fill blue -draw "circle 500,200 550,250" \
                -fill green -draw "polygon 200,400 300,350 400,400 300,450" \
                -fill black -pointsize 24 -gravity center -annotate +0+200 "PIXELATE THIS DETAILED IMAGE" \
                detailed_portrait.jpg
    }
}

# Set proper permissions
chown ga:ga detailed_portrait.jpg
chmod 644 detailed_portrait.jpg

echo "✅ Detailed portrait downloaded to /home/ga/Desktop/detailed_portrait.jpg"

echo "🎨 Opening GIMP with the detailed portrait..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/detailed_portrait.jpg > /tmp/gimp_pixelate.log 2>&1 &"

sleep 3

echo "=== Pixelate filter task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The detailed portrait is already open in GIMP"
echo "   2. Go to Filters → Blur → Pixelate (or Pixelize)"
echo "   3. In the Pixelate dialog:"
echo "      - Set pixel width/height to around 15 pixels"
echo "      - Observe the preview to see the mosaic effect"
echo "      - Adjust if needed for visible but not excessive pixelation"
echo "   4. Click OK to apply the filter"
echo "   5. The export will be automated after filtering"