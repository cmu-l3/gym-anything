#!/bin/bash
set -e

echo "=== Setting up sepia tone task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a vibrant color photograph suitable for sepia conversion
echo "📥 Downloading color photograph..."
cd /home/ga/Desktop/
wget -q -O color_photo.jpg "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O color_photo.jpg "https://images.unsplash.com/photo-1544005313-94ddf0286df2?ixlib=rb-4.0.3&auto=format&fit=crop&w=688&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a colorful test image if download fails
        convert -size 800x600 xc:white \
                -fill red -draw "rectangle 100,100 300,300" \
                -fill green -draw "rectangle 400,100 600,300" \
                -fill blue -draw "rectangle 250,350 550,550" \
                -fill black -pointsize 24 -gravity center -annotate +0+200 "CONVERT TO SEPIA" \
                color_photo.jpg
    }
}

# Set proper permissions
chown ga:ga color_photo.jpg
chmod 644 color_photo.jpg

echo "✅ Color photograph downloaded to /home/ga/Desktop/color_photo.jpg"

echo "🎨 Opening GIMP with the color photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/color_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Sepia tone task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The color photograph is already open in GIMP"
echo "   2. First, desaturate the image:"
echo "      - Go to Colors → Desaturate → Desaturate..."
echo "      - Choose Luminosity mode and click OK"
echo "   3. Then, apply sepia colorization:"
echo "      - Go to Colors → Colorize..."
echo "      - Set Hue to around 30-40 (yellow-brown range)"
echo "      - Set Saturation to around 25-35"
echo "      - Keep Lightness near 0"
echo "      - Click OK"
echo "   4. The export will be automated after editing"