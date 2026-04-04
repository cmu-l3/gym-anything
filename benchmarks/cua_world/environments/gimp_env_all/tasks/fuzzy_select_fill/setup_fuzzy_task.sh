#!/bin/bash
set -e

echo "=== Setting up fuzzy select and fill task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download product image with clear white background
echo "📥 Downloading product image with uniform background..."
cd /home/ga/Desktop/
wget -q -O product_image.jpg "https://images.unsplash.com/photo-1542291026-7eec264c27ff?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O product_image.jpg "https://images.unsplash.com/photo-1525966222134-fcfa99b8ae77?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear background if download fails
        convert -size 800x600 xc:white -fill black -draw "circle 400,300 500,300" -fill gray -pointsize 24 -gravity center -annotate +0+200 "SELECT BACKGROUND" product_image.jpg
    }
}

# Set proper permissions
chown ga:ga product_image.jpg
chmod 644 product_image.jpg

echo "✅ Product image downloaded to /home/ga/Desktop/product_image.jpg"

echo "🎨 Opening GIMP with the product image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/product_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Fuzzy select and fill task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The product image is already open in GIMP"
echo "   2. Select the Fuzzy Select tool (U key or from toolbox)"
echo "   3. Click on the white/uniform background area"
echo "   4. Adjust threshold if needed to select entire background"
echo "   5. Set foreground color to light blue RGB(173, 216, 230)"
echo "   6. Use Edit → Fill with FG Color to fill the selection"
echo "   7. Clear selection with Select → None"
echo "   8. The export will be automated after editing"