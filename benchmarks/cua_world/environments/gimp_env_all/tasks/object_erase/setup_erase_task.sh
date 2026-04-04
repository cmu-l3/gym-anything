#!/bin/bash
set -e

echo "=== Setting up object erase task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy imagemagick

# Create a simple image with a removable object using ImageMagick
echo "🎨 Creating test image with removable object..."
cd /home/ga/Desktop/

# Create a landscape image with a red circle to remove
convert -size 800x600 \
  -seed 42 plasma:lightblue-lightgreen \
  -blur 0x2 \
  \( -size 80x80 xc:transparent -fill red -draw "circle 40,40 40,10" \) \
  -gravity southeast -geometry +150+100 -composite \
  test_object_image.png

# Alternative: try downloading a real image with a simple object if convert fails
if [ ! -f "test_object_image.png" ]; then
    echo "📥 ImageMagick creation failed, downloading test image..."
    wget -q -O test_object_image.png "https://images.unsplash.com/photo-1441986300917-64674bd600d8?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600&q=80" || {
        echo "❌ Download failed, creating fallback image..."
        # Create a very simple fallback with just colored rectangles
        convert -size 800x600 xc:lightblue \
            -fill red -draw "rectangle 350,250 450,350" \
            test_object_image.png
    }
fi

# Set proper permissions
chown ga:ga test_object_image.png
chmod 644 test_object_image.png

echo "✅ Test image created at /home/ga/Desktop/test_object_image.png"

echo "🎨 Opening GIMP with the test image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/test_object_image.png > /tmp/gimp_erase.log 2>&1 &"

sleep 3

echo "=== Object erase task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The test image is already open in GIMP"
echo "   2. Select the Eraser Tool (E key or from toolbox)"
echo "   3. Adjust eraser size if needed (10-30 pixels recommended)"
echo "   4. Carefully erase the red object (circle or rectangle)"
echo "   5. Work systematically to remove all parts of the object"
echo "   6. Clean up edges for smooth transparency"
echo "   7. The export will be automated as PNG to preserve transparency"