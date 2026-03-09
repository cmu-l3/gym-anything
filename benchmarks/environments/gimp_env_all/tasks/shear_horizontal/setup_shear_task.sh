#!/bin/bash
set -e

echo "=== Setting up horizontal shear task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download or create a test image with clear vertical elements for shear visibility
echo "📥 Downloading test image with geometric patterns..."
cd /home/ga/Desktop/
wget -q -O test_shear.jpg "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O test_shear.jpg "https://images.unsplash.com/photo-1519452788759-976d5aa63d38?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, creating geometric test pattern..."
        # Create a test image with vertical lines if download fails
        convert -size 600x400 xc:white \
                -stroke black -strokewidth 3 \
                -draw "line 100,0 100,400" \
                -draw "line 200,0 200,400" \
                -draw "line 300,0 300,400" \
                -draw "line 400,0 400,400" \
                -draw "line 500,0 500,400" \
                -fill blue -pointsize 36 -gravity center \
                -annotate +0-100 "SHEAR TEST" \
                -fill red -pointsize 24 -gravity center \
                -annotate +0+100 "Vertical Lines" \
                test_shear.jpg
    }
}

# Set proper permissions
chown ga:ga test_shear.jpg
chmod 644 test_shear.jpg

echo "✅ Test image downloaded to /home/ga/Desktop/test_shear.jpg"

echo "🎨 Opening GIMP with the test image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/test_shear.jpg > /tmp/gimp_shear.log 2>&1 &"

sleep 3

echo "=== Horizontal shear task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The test image is already open in GIMP"
echo "   2. Go to Image → Transform → Shear (or Layer → Transform → Shear)"
echo "   3. In the Shear dialog, set horizontal shear to 50 pixels"
echo "   4. Keep vertical shear at 0 (no Y-axis shear)"
echo "   5. Click 'Shear' or 'Transform' to apply"
echo "   6. The export will be automated after transformation"