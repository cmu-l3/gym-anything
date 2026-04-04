#!/bin/bash
set -e

echo "=== Setting up auto-stretch contrast task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a flat, low-contrast image for testing
echo "📥 Downloading flat, low-contrast image..."
cd /home/ga/Desktop/
wget -q -O flat_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=50&sat=-80&con=-50" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flat_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=50&sat=-80&con=-50" || {
        echo "❌ All sources failed, creating fallback flat image..."
        # Create a simple flat/low-contrast test image if download fails
        convert -size 800x600 xc:"rgb(128,128,128)" -fill "rgb(140,140,140)" -draw "rectangle 100,100 700,500" -fill "rgb(120,120,120)" -draw "rectangle 200,200 600,400" -fill black -pointsize 24 -gravity center -annotate +0+100 "LOW CONTRAST IMAGE" flat_image.jpg
    }
}

# Set proper permissions
chown ga:ga flat_image.jpg
chmod 644 flat_image.jpg

echo "✅ Flat, low-contrast image downloaded to /home/ga/Desktop/flat_image.jpg"

echo "🎨 Opening GIMP with the flat image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flat_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Auto-stretch contrast task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The flat, low-contrast image is already open in GIMP"
echo "   2. Go to Colors → Auto → Stretch Contrast"
echo "   3. The operation will apply immediately (no dialog)"
echo "   4. Observe that the image now has better contrast and tonal range"
echo "   5. The export will be automated after editing"