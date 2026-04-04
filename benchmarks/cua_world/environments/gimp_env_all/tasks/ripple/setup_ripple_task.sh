#!/bin/bash
set -e

echo "=== Setting up ripple effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a photo image that will show ripple effects well
echo "📥 Downloading photo for ripple effect..."
cd /home/ga/Desktop/
wget -q -O photo_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with geometric patterns if download fails
        convert -size 800x600 xc:lightblue \
            -fill navy -draw "rectangle 100,100 300,300" \
            -fill white -draw "rectangle 500,200 700,400" \
            -fill black -pointsize 36 -gravity center -annotate +0+0 "RIPPLE TEST" \
            photo_image.jpg
    }
}

# Set proper permissions
chown ga:ga photo_image.jpg
chmod 644 photo_image.jpg

echo "✅ Photo image downloaded to /home/ga/Desktop/photo_image.jpg"

echo "🎨 Opening GIMP with the photo image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Ripple effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photo image is already open in GIMP"
echo "   2. Go to Filters → Distorts → Ripple"
echo "   3. In the Ripple dialog:"
echo "      - Adjust Amplitude (15-30 recommended for visible effect)"
echo "      - Adjust Wavelength (10-20 recommended)"
echo "      - Preview the effect if available"
echo "   4. Click OK to apply the ripple distortion"
echo "   5. The export will be automated after applying the effect"