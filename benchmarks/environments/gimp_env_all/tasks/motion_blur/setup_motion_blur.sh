#!/bin/bash
set -e

echo "=== Setting up motion blur task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with action/movement to blur
echo "📥 Downloading sports action image..."
cd /home/ga/Desktop/
wget -q -O sports_action.jpg "https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O sports_action.jpg "https://images.unsplash.com/photo-1594736797933-d0f06ba2fe65?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with directional elements if download fails
        convert -size 800x600 xc:lightblue -fill red -draw "rectangle 100,250 700,350 circle 150,300 50,300" -fill black -pointsize 24 -gravity center -annotate +0+150 "ADD MOTION BLUR" sports_action.jpg
    }
}

# Set proper permissions
chown ga:ga sports_action.jpg
chmod 644 sports_action.jpg

echo "✅ Sports action image downloaded to /home/ga/Desktop/sports_action.jpg"

echo "🎨 Opening GIMP with the sports action image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/sports_action.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Motion blur task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The sports action image is already open in GIMP"
echo "   2. Go to Filters → Blur → Motion Blur"
echo "   3. In the Motion Blur dialog:"
echo "      - Set the angle to 0° (horizontal motion)"
echo "      - Set the length/distance to around 20-30 pixels"
echo "      - Observe the preview to see the effect"
echo "   4. Click OK to apply the motion blur"
echo "   5. The export will be automated after editing"