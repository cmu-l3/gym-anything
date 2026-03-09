#!/bin/bash
set -e

echo "=== Setting up image rotation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a tilted landscape image for rotation correction
echo "📥 Downloading tilted landscape image..."
cd /home/ga/Desktop/
wget -q -O tilted_landscape.jpg "https://images.unsplash.com/photo-1519904981063-b0cf448d479e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80&sat=-10&con=10" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O tilted_landscape.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, creating test image..."
        # Create a simple test image with horizon line if download fails
        convert -size 800x600 xc:skyblue -fill darkgreen -draw "rectangle 0,400 800,600" -fill white -draw "line 50,350 750,380" -rotate 15 tilted_landscape.jpg
    }
}

# Set proper permissions
chown ga:ga tilted_landscape.jpg
chmod 644 tilted_landscape.jpg

echo "✅ Tilted landscape image downloaded to /home/ga/Desktop/tilted_landscape.jpg"

echo "🎨 Opening GIMP with the tilted landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/tilted_landscape.jpg > /tmp/gimp_rotate.log 2>&1 &"

sleep 3

echo "=== Image rotation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The tilted landscape image is already open in GIMP"
echo "   2. Select the Rotate Tool from toolbox (or press Shift+R)"
echo "   3. In the tool options panel, enter angle value: -15.0"
echo "   4. Click on the image to apply rotation preview"
echo "   5. Observe that horizon becomes more level"
echo "   6. Click 'Rotate' button to apply the transformation"
echo "   7. The export will be automated after rotation"
echo "   📝 Note: Use -15 degrees (negative) for clockwise rotation"