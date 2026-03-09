#!/bin/bash
set -e

echo "=== Setting up threshold conversion task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download grayscale image with good detail for thresholding
echo "📥 Downloading grayscale portrait image..."
cd /home/ga/Desktop/
wget -q -O grayscale_image.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80&sat=-100" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O grayscale_image.jpg "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?ixlib=rb-4.0.3&auto=format&fit=crop&w=700&q=80&sat=-100" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with varied tones if download fails
        convert -size 800x600 gradient:black-white -swirl 45 -blur 0x2 grayscale_image.jpg
    }
}

# Set proper permissions
chown ga:ga grayscale_image.jpg
chmod 644 grayscale_image.jpg

echo "✅ Grayscale image downloaded to /home/ga/Desktop/grayscale_image.jpg"

echo "🎨 Opening GIMP with the grayscale image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/grayscale_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Threshold conversion task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The grayscale image is already open in GIMP"
echo "   2. Go to Colors → Threshold"
echo "   3. In the Threshold dialog:"
echo "      - Observe the histogram showing intensity distribution"
echo "      - Adjust the threshold slider to separate light and dark"
echo "      - Typical range: set threshold around 120-140"
echo "      - Preview shows which pixels become black vs white"
echo "   4. Click OK to apply the threshold conversion"
echo "   5. The result should be pure black and white (binary)"
echo "   6. The export will be automated after editing"