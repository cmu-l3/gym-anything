#!/bin/bash
set -e

echo "=== Setting up cartoon effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear subject for cartoon effect
echo "📥 Downloading photograph for cartoon effect..."
cd /home/ga/Desktop/
wget -q -O photo_original.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_original.jpg "https://images.unsplash.com/photo-1552058544-f2b08422138a?ixlib=rb-4.0.3&auto=format&fit=crop&w=699&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear features if download fails
        convert -size 800x600 xc:lightblue -fill darkblue -draw "circle 300,200 300,100" -fill red -draw "rectangle 450,300 650,500" -fill black -pointsize 24 -gravity center -annotate +0+200 "CARTOON TEST" photo_original.jpg
    }
}

# Set proper permissions
chown ga:ga photo_original.jpg
chmod 644 photo_original.jpg

echo "✅ Photograph downloaded to /home/ga/Desktop/photo_original.jpg"

echo "🎨 Opening GIMP with the photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_original.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Cartoon effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photograph is already open in GIMP"
echo "   2. Go to Filters → Artistic → Cartoon"
echo "   3. The Cartoon filter dialog will open with preview"
echo "   4. You can adjust parameters if needed:"
echo "      - Mask radius: Controls edge smoothness (default ~7.0)"
echo "      - Percent black: Controls outline darkness (default ~0.2)"
echo "   5. Click OK to apply the cartoon effect"
echo "   6. The export will be automated after applying the filter"