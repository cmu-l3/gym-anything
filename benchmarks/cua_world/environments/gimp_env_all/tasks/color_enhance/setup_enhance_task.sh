#!/bin/bash
set -e

echo "=== Setting up color enhancement task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-opencv-python || {
    echo "OpenCV install failed, falling back to basic packages"
    apt-get install -y -qq python3-pil python3-numpy
}

# Download image with flat colors that would benefit from enhancement
echo "📥 Downloading flat/underexposed photograph..."
cd /home/ga/Desktop/
wget -q -O flat_photo.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=60&sat=-50&con=-30" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flat_photo.jpg "https://images.unsplash.com/photo-1447752875215-b2761acb3c5d?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=50" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with flat colors if download fails
        convert -size 800x600 xc:'rgb(100,80,70)' -fill 'rgb(120,100,90)' -draw "rectangle 200,150 600,450" -fill 'rgb(90,70,60)' -pointsize 24 -gravity center -annotate +0+100 "ENHANCE MY COLORS" flat_photo.jpg
    }
}

# Set proper permissions
chown ga:ga flat_photo.jpg
chmod 644 flat_photo.jpg

echo "✅ Flat photograph downloaded to /home/ga/Desktop/flat_photo.jpg"

echo "🎨 Opening GIMP with the flat photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flat_photo.jpg > /tmp/gimp_enhance.log 2>&1 &"

sleep 3

echo "=== Color enhancement task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The flat photograph is already open in GIMP"
echo "   2. Go to Colors → Auto → Color Enhance"
echo "   3. The enhancement will apply immediately (no dialog)"
echo "   4. Observe the improved color vibrancy and distribution"
echo "   5. The export will be automated after editing"