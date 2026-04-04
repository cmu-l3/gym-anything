#!/bin/bash
set -e

echo "=== Setting up auto white balance task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with prominent color cast (warm indoor lighting)
echo "📥 Downloading photo with color cast..."
cd /home/ga/Desktop/
wget -q -O color_cast_photo.jpg "https://images.unsplash.com/photo-1541746972996-4e0b0f93181f?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O color_cast_photo.jpg "https://images.unsplash.com/photo-1513475382585-d06e58bcb0e0?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with warm color cast if download fails
        convert -size 800x600 xc:"rgb(255,220,180)" -fill "rgb(200,180,160)" -draw "rectangle 200,200 600,400" -fill black -pointsize 24 -gravity center -annotate +0+100 "FIX WHITE BALANCE" color_cast_photo.jpg
    }
}

# Set proper permissions
chown ga:ga color_cast_photo.jpg
chmod 644 color_cast_photo.jpg

echo "✅ Color cast photo downloaded to /home/ga/Desktop/color_cast_photo.jpg"

echo "🎨 Opening GIMP with the color cast photo..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/color_cast_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Auto white balance task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The color cast photo is already open in GIMP"
echo "   2. Go to Colors → Auto → White Balance"
echo "   3. The correction will apply immediately"
echo "   4. Observe that the color cast is reduced/eliminated"
echo "   5. The export will be automated after correction"