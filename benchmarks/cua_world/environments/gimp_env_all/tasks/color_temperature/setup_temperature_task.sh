#!/bin/bash
set -e

echo "=== Setting up color temperature task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with color temperature issues (cool/blue bias)
echo "📥 Downloading photo with color cast..."
cd /home/ga/Desktop/
wget -q -O photo_with_cast.jpg "https://images.unsplash.com/photo-1551632436-cbf8dd35adfa?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_with_cast.jpg "https://images.unsplash.com/photo-1548802673-380ab8ebc7b7?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a cool-tinted test image if download fails
        convert -size 800x600 xc:'rgb(180,190,220)' -fill 'rgb(100,120,160)' -draw "rectangle 100,100 700,500" -pointsize 24 -gravity center -annotate +0+0 "ADJUST COLOR TEMPERATURE" photo_with_cast.jpg
    }
}

# Set proper permissions
chown ga:ga photo_with_cast.jpg
chmod 644 photo_with_cast.jpg

echo "✅ Photo with color cast downloaded to /home/ga/Desktop/photo_with_cast.jpg"

echo "🎨 Opening GIMP with the photo..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_with_cast.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Color temperature task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photo is already open in GIMP"
echo "   2. Go to Colors → Color Temperature"
echo "   3. Enable Preview to see changes in real-time"
echo "   4. Adjust the temperature slider to warm up the image"
echo "   5. Move slider to the right for warmer (yellow/orange)"
echo "   6. Move slider significantly (+50 to +100 units recommended)"
echo "   7. Click OK to apply the temperature adjustment"
echo "   8. The export will be automated after editing"