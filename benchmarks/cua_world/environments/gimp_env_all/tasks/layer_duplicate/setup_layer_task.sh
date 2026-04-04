#!/bin/bash
set -e

echo "=== Setting up layer duplication task ==="

# Install required packages for XCF file processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with clear subject for layer duplication
echo "📥 Downloading flower image..."
cd /home/ga/Desktop/
wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1426604966848-d7adac402bff?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 600x400 xc:lightgreen -fill yellow -draw "circle 300,200 200,100" -fill black -pointsize 24 -gravity center -annotate +0+150 "DUPLICATE LAYER" flower_image.jpg
    }
}

# Set proper permissions
chown ga:ga flower_image.jpg
chmod 644 flower_image.jpg

echo "✅ Flower image downloaded to /home/ga/Desktop/flower_image.jpg"

echo "🎨 Opening GIMP with the flower image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flower_image.jpg > /tmp/gimp_layer.log 2>&1 &"

sleep 3

echo "=== Layer duplication task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The flower image is already open in GIMP"
echo "   2. You should see the Layers panel (usually on the right side)"
echo "   3. The image currently has 1 layer (typically named 'Background')"
echo "   4. Right-click on the layer in the Layers panel"
echo "   5. Select 'Duplicate Layer' from the context menu"
echo "   6. Alternatively, go to Layer → Duplicate Layer in the menu"
echo "   7. Verify that you now have 2 layers in the Layers panel"
echo "   8. The export will be automated after editing"