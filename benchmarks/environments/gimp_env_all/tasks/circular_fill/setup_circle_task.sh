#!/bin/bash
set -e

echo "=== Setting up circular selection and fill task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image suitable for circular selection
echo "📥 Downloading test image..."
cd /home/ga/Desktop/
wget -q -O circle_test_image.jpg "https://images.unsplash.com/photo-1519904981063-b0cf448d479e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O circle_test_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 600x400 xc:lightgray -fill darkblue -draw "rectangle 50,50 550,350" -fill white -pointsize 24 -gravity center -annotate +0+0 "CREATE CIRCLE HERE" circle_test_image.jpg
    }
}

# Set proper permissions
chown ga:ga circle_test_image.jpg
chmod 644 circle_test_image.jpg

echo "✅ Test image downloaded to /home/ga/Desktop/circle_test_image.jpg"

echo "🎨 Opening GIMP with the test image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/circle_test_image.jpg > /tmp/gimp_circle.log 2>&1 &"

sleep 3

echo "=== Circular fill task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The test image is already open in GIMP"
echo "   2. Select the Ellipse Select Tool (E key or from toolbox)"
echo "   3. Click and drag to create a circular selection in the center"
echo "   4. Make the selection reasonably large but not edge-to-edge"
echo "   5. Set foreground color to a bright color (red, yellow, etc.)"
echo "   6. Fill the selection using Edit → Fill with FG Color"
echo "   7. Optionally deselect with Select → None"
echo "   8. The export will be automated after editing"