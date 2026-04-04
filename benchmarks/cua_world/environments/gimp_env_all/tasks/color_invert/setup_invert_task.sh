#!/bin/bash
set -e

echo "=== Setting up color inversion task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with good color range for inversion
echo "📥 Downloading colorful photograph..."
cd /home/ga/Desktop/
wget -q -O original_photo.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O original_photo.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a colorful test image if download fails
        convert -size 800x600 xc:white \
            -fill red -draw "rectangle 0,0 266,200" \
            -fill green -draw "rectangle 266,0 533,200" \
            -fill blue -draw "rectangle 533,0 800,200" \
            -fill yellow -draw "rectangle 0,200 266,400" \
            -fill cyan -draw "rectangle 266,200 533,400" \
            -fill magenta -draw "rectangle 533,200 800,400" \
            -fill black -draw "rectangle 0,400 800,600" \
            -fill white -pointsize 36 -gravity center -annotate +0+0 "INVERT COLORS" \
            original_photo.jpg
    }
}

# Set proper permissions
chown ga:ga original_photo.jpg
chmod 644 original_photo.jpg

echo "✅ Colorful photograph downloaded to /home/ga/Desktop/original_photo.jpg"

echo "🎨 Opening GIMP with the photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/original_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Color inversion task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The colorful photograph is already open in GIMP"
echo "   2. Go to Colors → Invert in the menu bar"
echo "   3. The inversion will apply immediately"
echo "   4. Verify that colors are inverted (light becomes dark, etc.)"
echo "   5. The export will be automated after editing"