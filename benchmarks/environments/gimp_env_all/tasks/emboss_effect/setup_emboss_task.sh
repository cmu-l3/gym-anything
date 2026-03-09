#!/bin/bash
set -e

echo "=== Setting up emboss effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-opencv-python || {
    echo "Installing fallback packages..."
    apt-get install -y -qq python3-pil python3-numpy
}

# Download image with good contrast for emboss effect
echo "📥 Downloading high-contrast image..."
cd /home/ga/Desktop/
wget -q -O emboss_input.jpg "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O emboss_input.jpg "https://images.unsplash.com/photo-1541888946425-d81bb19240f5?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with high contrast elements if download fails
        convert -size 800x600 xc:white -fill black -pointsize 72 -font Arial-Bold -gravity center -annotate +0+0 "EMBOSS\nTEST" emboss_input.jpg
    }
}

# Set proper permissions
chown ga:ga emboss_input.jpg
chmod 644 emboss_input.jpg

echo "✅ High-contrast image downloaded to /home/ga/Desktop/emboss_input.jpg"

echo "🎨 Opening GIMP with the image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/emboss_input.jpg > /tmp/gimp_emboss.log 2>&1 &"

sleep 3

echo "=== Emboss effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The high-contrast image is already open in GIMP"
echo "   2. Go to Filters → Distorts → Emboss"
echo "   3. The emboss dialog will show preview and parameters"
echo "   4. Default parameters usually work well (can be adjusted if needed)"
echo "   5. Click OK to apply the emboss effect"
echo "   6. The export will be automated after editing"