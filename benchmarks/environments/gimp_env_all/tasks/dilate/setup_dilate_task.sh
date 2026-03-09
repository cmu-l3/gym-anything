#!/bin/bash
set -e

echo "=== Setting up dilate morphological filter task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear edges and contrasts suitable for dilation
echo "📥 Downloading image with clear boundaries for dilation..."
cd /home/ga/Desktop/
wget -q -O edge_image.jpg "https://images.unsplash.com/photo-1518709268805-4e9042af2176?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O edge_image.jpg "https://images.unsplash.com/photo-1557804506-669a67965ba0?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear edges if download fails
        convert -size 600x400 xc:black -fill white -draw "circle 150,150 150,220" -fill white -draw "rectangle 350,100 550,300" -fill black -pointsize 24 -gravity center -annotate +0+150 "DILATE FILTER TEST" edge_image.jpg
    }
}

# Set proper permissions
chown ga:ga edge_image.jpg
chmod 644 edge_image.jpg

echo "✅ Edge image downloaded to /home/ga/Desktop/edge_image.jpg"

echo "🎨 Opening GIMP with the edge image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/edge_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Dilate task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The edge image is already open in GIMP"
echo "   2. Go to Filters → Generic → Dilate"
echo "   3. The filter will apply immediately (no dialog)"
echo "   4. Observe that bright regions have expanded slightly"
echo "   5. The export will be automated after applying the filter"