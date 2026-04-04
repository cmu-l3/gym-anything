#!/bin/bash
set -e

echo "=== Setting up edge detection task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear edges and subjects
echo "📥 Downloading sample image for edge detection..."
cd /home/ga/Desktop/
wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear edges if download fails
        convert -size 800x600 xc:white -fill black -draw "rectangle 150,150 650,450" -fill gray -draw "circle 400,300 400,200" -pointsize 36 -gravity center -annotate +0+0 "EDGE DETECTION" sample_image.jpg
    }
}

# Set proper permissions
chown ga:ga sample_image.jpg
chmod 644 sample_image.jpg

echo "✅ Sample image downloaded to /home/ga/Desktop/sample_image.jpg"

echo "🎨 Opening GIMP with the sample image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/sample_image.jpg > /tmp/gimp_edge_task.log 2>&1 &"

sleep 3

echo "=== Edge detection task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The sample image is already open in GIMP"
echo "   2. Go to Filters → Edge-Detect → Edge..."
echo "   3. The Edge Detection dialog will open with preview"
echo "   4. Default settings (Sobel algorithm) work well"
echo "   5. Click OK to apply the edge detection filter"
echo "   6. The result should show bright edges on dark background"
echo "   7. The export will be automated after applying the filter"