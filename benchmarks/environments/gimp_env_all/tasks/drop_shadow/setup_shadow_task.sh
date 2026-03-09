#!/bin/bash
set -e

echo "=== Setting up drop shadow task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with text/logo suitable for drop shadow
echo "📥 Downloading logo image..."
cd /home/ga/Desktop/
wget -q -O logo_image.png "https://images.unsplash.com/photo-1611224923853-80b023f02d71?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O logo_image.png "https://images.unsplash.com/photo-1572044162444-ad60f128bdea?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, creating fallback..."
        # Create a simple logo/text image if download fails
        convert -size 800x600 xc:white -fill black -font Arial-Bold -pointsize 72 -gravity center -annotate +0+0 "LOGO" -trim -border 50x50 -bordercolor white logo_image.png
    }
}

# Set proper permissions
chown ga:ga logo_image.png
chmod 644 logo_image.png

echo "✅ Logo image downloaded to /home/ga/Desktop/logo_image.png"

echo "🎨 Opening GIMP with the logo image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/logo_image.png > /tmp/gimp_shadow.log 2>&1 &"

sleep 3

echo "=== Drop shadow task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The logo/text image is already open in GIMP"
echo "   2. Navigate to Filters → Light and Shadow → Drop Shadow"
echo "   3. In the Drop Shadow dialog:"
echo "      - Set X offset to 5-8 pixels (shadow to the right)"
echo "      - Set Y offset to 5-8 pixels (shadow downward)" 
echo "      - Set opacity to 50-75% for natural appearance"
echo "      - Set blur radius to 10-15 pixels for soft edges"
echo "      - Keep shadow color black or dark gray"
echo "   4. Click OK to apply the drop shadow effect"
echo "   5. The export will be automated after editing"