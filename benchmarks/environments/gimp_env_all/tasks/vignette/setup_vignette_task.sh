#!/bin/bash
set -e

echo "=== Setting up vignette effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a portrait image suitable for vignette effect
echo "📥 Downloading portrait image..."
cd /home/ga/Desktop/
wget -q -O portrait_image.jpg "https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=688&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O portrait_image.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&auto=format&fit=crop&w=687&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightblue -fill darkblue -draw "circle 400,300 400,200" -fill white -pointsize 32 -gravity center -annotate +0+0 "APPLY VIGNETTE" portrait_image.jpg
    }
}

# Set proper permissions
chown ga:ga portrait_image.jpg
chmod 644 portrait_image.jpg

echo "✅ Portrait image downloaded to /home/ga/Desktop/portrait_image.jpg"

echo "🎨 Opening GIMP with the portrait image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/portrait_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Vignette effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait image is already open in GIMP"
echo "   2. Go to Filters → Light and Shadow → Vignette"
echo "   3. Review the preview in the dialog (should show darkened edges)"
echo "   4. The default settings are usually good - click OK to apply"
echo "   5. Alternatively, adjust Softness/Radius if needed for better effect"
echo "   6. Click OK to apply the vignette effect"
echo "   7. The export will be automated after applying the effect"