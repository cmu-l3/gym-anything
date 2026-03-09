#!/bin/bash
set -e

echo "=== Setting up shadows-highlights adjustment task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with dark shadows that need recovery
echo "📥 Downloading high-contrast image with dark shadows..."
cd /home/ga/Desktop/
wget -q -O high_contrast_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O high_contrast_image.jpg "https://images.unsplash.com/photo-1469474968028-56623f02e42e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with dark areas if download fails
        convert -size 800x600 xc:white \
                -fill black -draw "rectangle 0,300 800,600" \
                -fill gray30 -draw "rectangle 100,350 700,550" \
                -fill black -pointsize 24 -gravity center -annotate +0+100 "BRIGHTEN SHADOWS" \
                high_contrast_image.jpg
    }
}

# Set proper permissions
chown ga:ga high_contrast_image.jpg
chmod 644 high_contrast_image.jpg

echo "✅ High-contrast image downloaded to /home/ga/Desktop/high_contrast_image.jpg"

echo "🎨 Opening GIMP with the high-contrast image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/high_contrast_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Shadows-highlights adjustment task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The high-contrast image is already open in GIMP"
echo "   2. Go to Colors → Shadows-Highlights"
echo "   3. In the Shadows-Highlights dialog:"
echo "      - Increase the Shadows slider (try 40-60) to brighten dark areas"
echo "      - Optionally adjust Highlights if needed"
echo "      - Preview the changes to see shadow detail recovery"
echo "   4. Click OK to apply the adjustment"
echo "   5. The export will be automated after editing"