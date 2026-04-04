#!/bin/bash
set -e

echo "=== Setting up cubism effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image suitable for cubism effect (portrait with good contrast)
echo "📥 Downloading portrait image for cubism effect..."
cd /home/ga/Desktop/
wget -q -O cubism_photo.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O cubism_photo.jpg "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with geometric elements if download fails
        convert -size 800x600 xc:white -fill blue -draw "circle 200,200 150,150" -fill red -draw "rectangle 400,100 600,300" -fill green -draw "polygon 100,500 300,400 200,550" -fill black -pointsize 24 -gravity center -annotate +0+200 "APPLY CUBISM" cubism_photo.jpg
    }
}

# Set proper permissions
chown ga:ga cubism_photo.jpg
chmod 644 cubism_photo.jpg

echo "✅ Photo downloaded to /home/ga/Desktop/cubism_photo.jpg"

echo "🎨 Opening GIMP with the photo..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/cubism_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Cubism effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photo is already open in GIMP"
echo "   2. Go to Filters → Artistic → Cubism (or Filters → Blur → Cubism in some versions)"
echo "   3. In the Cubism dialog:"
echo "      - Adjust Tile size if needed (typically 10-20 pixels)"
echo "      - Keep other settings at default or adjust for better effect"
echo "      - Use preview to see the effect"
echo "   4. Click OK to apply the cubism effect"
echo "   5. The export will be automated after editing"