#!/bin/bash
set -e

echo "=== Setting up image offset task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear asymmetric features for offset visibility
echo "📥 Downloading pattern image..."
cd /home/ga/Desktop/
wget -q -O pattern_image.jpg "https://images.unsplash.com/photo-1557804506-669a67965ba0?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O pattern_image.jpg "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear asymmetric pattern if download fails
        convert -size 600x400 xc:white \
                -fill red -draw "rectangle 50,50 150,150" \
                -fill blue -draw "rectangle 450,50 550,150" \
                -fill green -draw "rectangle 50,250 150,350" \
                -fill yellow -draw "rectangle 450,250 550,350" \
                -fill black -pointsize 24 -gravity center -annotate +0-100 "OFFSET TEST" \
                pattern_image.jpg
    }
}

# Set proper permissions
chown ga:ga pattern_image.jpg
chmod 644 pattern_image.jpg

echo "✅ Pattern image downloaded to /home/ga/Desktop/pattern_image.jpg"

echo "🎨 Opening GIMP with the pattern image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/pattern_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Image offset task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The pattern image is already open in GIMP"
echo "   2. Go to Layer → Transform → Offset"
echo "   3. Set X offset to 150 pixels (rightward)"
echo "   4. Set Y offset to 100 pixels (downward)"
echo "   5. Ensure 'Wrap around' option is enabled"
echo "   6. Click OK to apply the offset"
echo "   7. The export will be automated after editing"