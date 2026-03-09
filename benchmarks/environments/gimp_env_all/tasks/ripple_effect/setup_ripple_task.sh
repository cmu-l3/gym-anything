#!/bin/bash
set -e

echo "=== Setting up ripple effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear geometric features for ripple effect
echo "📥 Downloading geometric landscape image..."
cd /home/ga/Desktop/
wget -q -O geometric_image.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O geometric_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with geometric patterns if download fails
        convert -size 800x600 xc:lightblue -stroke black -strokewidth 2 -draw "line 0,150 800,150" -draw "line 0,300 800,300" -draw "line 0,450 800,450" -fill black -pointsize 24 -gravity center -annotate +0+100 "APPLY RIPPLE EFFECT" geometric_image.jpg
    }
}

# Set proper permissions
chown ga:ga geometric_image.jpg
chmod 644 geometric_image.jpg

echo "✅ Geometric image downloaded to /home/ga/Desktop/geometric_image.jpg"

echo "🎨 Opening GIMP with the geometric image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/geometric_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Ripple effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The geometric image is already open in GIMP"
echo "   2. Go to Filters → Distorts → Ripple"
echo "   3. In the Ripple dialog:"
echo "      - Set Amplitude to a moderate value (10-25 pixels)"
echo "      - Set Wavelength to a moderate value (20-50 pixels)"
echo "      - Leave other settings at defaults"
echo "   4. Click OK to apply the ripple effect"
echo "   5. The export will be automated after editing"