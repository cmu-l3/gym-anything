#!/bin/bash
set -e

echo "=== Setting up layer duplication task ==="

# Install required packages for verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a simple image for layer duplication
echo "📥 Downloading test image..."
cd /home/ga/Desktop/
wget -q -O simple_image.jpg "https://images.unsplash.com/photo-1575936123452-b67c3203c357?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O simple_image.jpg "https://images.unsplash.com/photo-1541963463532-d68292c34d19?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, creating test image..."
        # Create a simple test image if download fails
        convert -size 400x300 xc:lightblue -fill red -draw "circle 200,150 280,150" -fill black -pointsize 24 -gravity center -annotate +0+0 "DUPLICATE LAYER" simple_image.jpg
    }
}

# Set proper permissions
chown ga:ga simple_image.jpg
chmod 644 simple_image.jpg

echo "✅ Simple image downloaded to /home/ga/Desktop/simple_image.jpg"

echo "🎨 Opening GIMP with the simple image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/simple_image.jpg > /tmp/gimp_layer.log 2>&1 &"

sleep 3

echo "=== Layer duplication task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The simple image is already open in GIMP"
echo "   2. Use Layer → Duplicate Layer (or right-click on layer in Layers panel)"  
echo "   3. Alternative: Use keyboard shortcut Shift+Ctrl+D"
echo "   4. Verify there are now 2 layers in the Layers panel"
echo "   5. The duplicated layer should appear above the original"
echo "   6. The XCF export will be automated to preserve layer structure"