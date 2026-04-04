#!/bin/bash
set -e

echo "=== Setting up wind effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear edges and defined subjects where wind effect will be visible
echo "📥 Downloading portrait image for wind effect..."
cd /home/ga/Desktop/
wget -q -O wind_subject.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O wind_subject.jpg "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?ixlib=rb-4.0.3&auto=format&fit=crop&w=687&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with clear edges if download fails
        convert -size 800x600 xc:white -fill black -draw "rectangle 300,200 500,400" -fill red -draw "circle 400,300 400,350" wind_subject.jpg
    }
}

# Set proper permissions
chown ga:ga wind_subject.jpg
chmod 644 wind_subject.jpg

echo "✅ Wind subject image downloaded to /home/ga/Desktop/wind_subject.jpg"

echo "🎨 Opening GIMP with the wind subject image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/wind_subject.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Wind effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The subject image is already open in GIMP"
echo "   2. Go to Filters → Distorts → Wind"
echo "   3. In the Wind dialog:"
echo "      - Choose a direction (Left, Right, Top, or Bottom)"
echo "      - Set strength between 10-30 for visible but not overwhelming effect"
echo "      - Use preview to assess the effect"
echo "   4. Click OK to apply the wind effect"
echo "   5. The export will be automated after editing"