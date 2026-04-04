#!/bin/bash
set -e

echo "=== Setting up emboss effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with good detail and edges for emboss effect
echo "📥 Downloading detailed photograph..."
cd /home/ga/Desktop/
wget -q -O detailed_photo.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O detailed_photo.jpg "https://images.unsplash.com/photo-1541963463532-d68292c34d19?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with geometric patterns if download fails
        convert -size 800x600 xc:lightblue \
                -fill red -draw "rectangle 100,100 300,300" \
                -fill green -draw "circle 500,200 600,250" \
                -fill yellow -draw "polygon 200,400 350,400 275,500" \
                -fill black -pointsize 36 -gravity center \
                -annotate +0+0 "TEST EMBOSS IMAGE" detailed_photo.jpg
    }
}

# Set proper permissions
chown ga:ga detailed_photo.jpg
chmod 644 detailed_photo.jpg

echo "✅ Detailed photograph downloaded to /home/ga/Desktop/detailed_photo.jpg"

echo "🎨 Opening GIMP with the detailed photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/detailed_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Emboss effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The detailed photograph is already open in GIMP"
echo "   2. Go to Filters → Distorts → Emboss..."
echo "   3. In the Emboss dialog:"
echo "      - Azimuth (light direction): typically 135° (default is good)"
echo "      - Elevation (light angle): typically 45° (default is good)"
echo "      - Depth (effect intensity): 3-10 (adjust for desired relief strength)"
echo "   4. Preview the effect and adjust if needed"
echo "   5. Click OK to apply the emboss filter"
echo "   6. The result should be a grayscale relief with 3D appearance"
echo "   7. The export will be automated after applying the filter"