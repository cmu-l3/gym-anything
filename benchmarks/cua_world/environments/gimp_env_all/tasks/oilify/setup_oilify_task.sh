#!/bin/bash
set -e

echo "=== Setting up oil painting effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a photograph suitable for oil painting effect
echo "📥 Downloading photograph for oil painting..."
cd /home/ga/Desktop/
wget -q -O photo_for_oilify.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_for_oilify.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with varied colors if download fails
        convert -size 800x600 xc:white \
                -fill red -draw "circle 200,150 150,100" \
                -fill blue -draw "circle 400,200 350,150" \
                -fill green -draw "circle 600,300 550,250" \
                -fill yellow -draw "rectangle 100,400 700,500" \
                photo_for_oilify.jpg
    }
}

# Set proper permissions
chown ga:ga photo_for_oilify.jpg
chmod 644 photo_for_oilify.jpg

echo "✅ Photograph downloaded to /home/ga/Desktop/photo_for_oilify.jpg"

echo "🎨 Opening GIMP with the photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_for_oilify.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Oil painting effect task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photograph is already open in GIMP"
echo "   2. Go to Filters → Artistic → Oilify..."
echo "   3. In the Oilify dialog:"
echo "      - Set Mask Size to a moderate value (7-10 pixels)"
echo "      - Enable Preview to see the effect"
echo "   4. Click OK to apply the oil painting effect"
echo "   5. The export will be automated after applying the filter"