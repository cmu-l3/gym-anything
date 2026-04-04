#!/bin/bash
set -e

echo "=== Setting up threshold conversion task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download grayscale landscape image suitable for threshold conversion
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_grayscale.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_grayscale.jpg "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with varying grayscale values if download fails
        convert -size 800x600 gradient:black-white -blur 0x5 landscape_grayscale.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_grayscale.jpg
chmod 644 landscape_grayscale.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_grayscale.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_grayscale.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Threshold conversion task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Go to Colors → Threshold in the menu bar"
echo "   3. In the Threshold dialog:"
echo "      - Observe the histogram showing brightness distribution"
echo "      - Adjust the threshold sliders to create good black/white separation"
echo "      - Use the preview to see the effect in real-time"
echo "      - Aim for a balance that preserves important details"
echo "   4. Click OK to apply the threshold conversion"
echo "   5. The export will be automated after editing"