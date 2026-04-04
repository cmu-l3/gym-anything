#!/bin/bash
set -e

echo "=== Setting up layer mask task ==="

# Install required packages for XCF file analysis
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a simple image for layer mask testing
echo "📥 Downloading test image..."
cd /home/ga/Desktop/
wget -q -O mask_test_image.jpg "https://images.unsplash.com/photo-1560472354-b33ff0c44a43?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O mask_test_image.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 600x400 gradient:blue-yellow mask_test_image.jpg
    }
}

# Set proper permissions
chown ga:ga mask_test_image.jpg
chmod 644 mask_test_image.jpg

echo "✅ Test image downloaded to /home/ga/Desktop/mask_test_image.jpg"

echo "🎨 Opening GIMP with the test image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/mask_test_image.jpg > /tmp/gimp_mask.log 2>&1 &"

sleep 3

echo "=== Layer mask task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The test image is already open in GIMP"
echo "   2. Go to Layer → Mask → Add Layer Mask"
echo "   3. In the dialog, select 'White (full opacity)'"
echo "   4. Click 'Add' to create the mask"
echo "   5. Check the Layers panel - you should see a mask thumbnail next to the layer"
echo "   6. The save will be automated after adding the mask"