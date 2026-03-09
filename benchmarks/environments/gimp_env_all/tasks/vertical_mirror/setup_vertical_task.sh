#!/bin/bash
set -e

echo "=== Setting up vertical mirror task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with distinctive top/bottom features for easy verification
echo "📥 Downloading flower image..."
cd /home/ga/Desktop/
wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1490750967868-88aa4486c946?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flower_image.jpg "https://images.unsplash.com/photo-1592194996308-7b43878e84a6?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with asymmetric vertical features if download fails
        convert -size 600x800 xc:lightblue -fill red -draw "rectangle 200,100 400,200" -fill green -draw "rectangle 150,600 450,700" -fill black -pointsize 24 -gravity center -annotate +0-200 "TOP" -annotate +0+200 "BOTTOM" flower_image.jpg
    }
}

# Set proper permissions
chown ga:ga flower_image.jpg
chmod 644 flower_image.jpg

echo "✅ Flower image downloaded to /home/ga/Desktop/flower_image.jpg"

echo "🎨 Opening GIMP with the flower image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flower_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Vertical mirror task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The flower image is already open in GIMP"
echo "   2. Go to Image → Transform → Flip Vertical (NOT Flip Horizontal)"
echo "   3. The operation should apply immediately"
echo "   4. Verify that top and bottom portions have been swapped"
echo "   5. The export will be automated after editing"