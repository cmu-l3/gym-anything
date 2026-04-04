#!/bin/bash
set -e

echo "=== Setting up contrast adjustment task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image with low contrast that would benefit from adjustment
echo "📥 Downloading low-contrast landscape image..."
cd /home/ga/Desktop/
wget -q -O low_contrast_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=60" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O low_contrast_image.jpg "https://images.unsplash.com/photo-1445965047888-ccda90bb8b3e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=60" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple low-contrast test image if download fails
        convert -size 800x600 gradient:gray30-gray70 -pointsize 32 -fill gray50 -gravity center -annotate +0+0 "INCREASE CONTRAST" low_contrast_image.jpg
    }
}

# Set proper permissions
chown ga:ga low_contrast_image.jpg
chmod 644 low_contrast_image.jpg

echo "✅ Low-contrast image downloaded to /home/ga/Desktop/low_contrast_image.jpg"

echo "🎨 Opening GIMP with the low-contrast image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/low_contrast_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Contrast adjustment task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The low-contrast image is already open in GIMP"
echo "   2. Go to Colors → Brightness-Contrast"
echo "   3. In the dialog, increase the Contrast slider (try +20 to +40)"
echo "   4. Observe the real-time preview showing enhanced tonal separation"
echo "   5. Click OK to apply the contrast adjustment"
echo "   6. The export will be automated after editing"