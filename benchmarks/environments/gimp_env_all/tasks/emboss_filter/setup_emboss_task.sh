#!/bin/bash
set -e

echo "=== Setting up emboss filter task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with good detail for emboss effect
echo "📥 Downloading detailed portrait image..."
cd /home/ga/Desktop/
wget -q -O portrait_detail.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O portrait_detail.jpg "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?ixlib=rb-4.0.3&auto=format&fit=crop&w=687&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with geometric patterns if download fails
        convert -size 600x600 xc:white -fill black -draw "rectangle 100,100 200,200" -fill gray -draw "ellipse 400,300 100,80" -pointsize 24 -gravity center -annotate +0+0 "EMBOSS TEST" portrait_detail.jpg
    }
}

# Set proper permissions
chown ga:ga portrait_detail.jpg
chmod 644 portrait_detail.jpg

echo "✅ Portrait image downloaded to /home/ga/Desktop/portrait_detail.jpg"

echo "🎨 Opening GIMP with the portrait image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/portrait_detail.jpg > /tmp/gimp_emboss_task.log 2>&1 &"

sleep 3

echo "=== Emboss filter task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait image is already open in GIMP"
echo "   2. Go to Filters → Artistic → Emboss (or Filters → Distorts → Emboss)"
echo "   3. In the Emboss dialog, review the preview"
echo "   4. The default settings should work well, but you can adjust if needed"
echo "   5. Click OK to apply the emboss effect"
echo "   6. The export will be automated after applying the filter"