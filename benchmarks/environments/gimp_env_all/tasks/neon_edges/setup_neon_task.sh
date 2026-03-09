#!/bin/bash
set -e

echo "=== Setting up neon edge effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear edges and good contrast
echo "📥 Downloading photo with clear edges..."
cd /home/ga/Desktop/
wget -q -O edge_photo.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O edge_photo.jpg "https://images.unsplash.com/photo-1519904981063-b0cf448d479e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear edges if download fails
        convert -size 800x600 xc:lightblue -fill white -draw "circle 400,300 500,300" -fill black -draw "rectangle 200,100 600,200" edge_photo.jpg
    }
}

# Set proper permissions
chown ga:ga edge_photo.jpg
chmod 644 edge_photo.jpg

echo "✅ Edge photo downloaded to /home/ga/Desktop/edge_photo.jpg"

echo "🎨 Opening GIMP with the edge photo..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/edge_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Neon edge effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photo is already open in GIMP"
echo "   2. Go to Filters → Edge-Detect → Neon..."
echo "   3. In the Neon dialog:"
echo "      - Set Radius to around 5-10 pixels (or keep default)"
echo "      - Keep Amount at default value"
echo "      - Preview should show bright edges on dark background"
echo "   4. Click OK to apply the neon effect"
echo "   5. Wait for the filter to process"
echo "   6. The export will be automated after editing"