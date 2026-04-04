#!/bin/bash
set -e

echo "=== Setting up color sampling task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with prominent purple flowers
echo "📥 Downloading flower garden image..."
cd /home/ga/Desktop/
wget -q -O flower_garden.jpg "https://images.unsplash.com/photo-1490750967868-88aa4486c946?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flower_garden.jpg "https://images.unsplash.com/photo-1416879595882-3373a0480b5b?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with purple elements if download fails
        convert -size 800x600 xc:lightgreen -fill purple -draw "circle 300,150 350,200" -fill black -pointsize 16 -gravity center -annotate +0+200 "SAMPLE PURPLE COLOR" flower_garden.jpg
    }
}

# Set proper permissions
chown ga:ga flower_garden.jpg
chmod 644 flower_garden.jpg

echo "✅ Flower garden image downloaded to /home/ga/Desktop/flower_garden.jpg"

echo "🎨 Opening GIMP with the flower garden image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flower_garden.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Color sampling task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The flower garden image is already open in GIMP"
echo "   2. Select the Eyedropper/Color Picker tool (I key or from toolbox)"
echo "   3. Click on the purple flower in the upper area to sample its color"
echo "   4. Select the Rectangle Select tool (R key or from toolbox)"
echo "   5. Create a rectangular selection in the lower-left area"
echo "   6. Use Edit → Fill with Foreground Color or Bucket Fill tool"
echo "   7. Fill the selection with the sampled purple color"
echo "   8. Deselect the selection (Select → None)"
echo "   9. The export will be automated after editing"