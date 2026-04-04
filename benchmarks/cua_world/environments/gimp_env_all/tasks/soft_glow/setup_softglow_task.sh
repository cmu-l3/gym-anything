#!/bin/bash
set -e

echo "=== Setting up soft glow effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a portrait image suitable for soft glow effect
echo "📥 Downloading portrait image..."
cd /home/ga/Desktop/
wget -q -O portrait_softglow.jpg "https://images.unsplash.com/photo-1544005313-94ddf0286df2?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=688&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O portrait_softglow.jpg "https://images.unsplash.com/photo-1531123897727-8f129e1688ce?ixlib=rb-4.0.3&auto=format&fit=crop&w=687&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with bright areas if download fails
        convert -size 800x600 gradient:lightblue-white -blur 5x5 -pointsize 36 -fill yellow -gravity north -annotate +0+50 "TEST PORTRAIT" portrait_softglow.jpg
    }
}

# Set proper permissions
chown ga:ga portrait_softglow.jpg
chmod 644 portrait_softglow.jpg

echo "✅ Portrait image downloaded to /home/ga/Desktop/portrait_softglow.jpg"

echo "🎨 Opening GIMP with the portrait image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/portrait_softglow.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Soft glow task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait image is already open in GIMP"
echo "   2. Go to Filters → Light and Shadow → Softglow"
echo "   3. In the Softglow dialog:"
echo "      - Observe the preview effect"
echo "      - Adjust Glow radius to 10-15 pixels for optimal effect"
echo "      - Adjust brightness/sharpness if available"
echo "   4. Click OK to apply the soft glow effect"
echo "   5. The export will be automated after applying the effect"