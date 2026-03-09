#!/bin/bash
set -e

echo "=== Setting up colorize task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with diverse colors suitable for colorization
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_color.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&h=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_color.jpg "https://images.unsplash.com/photo-1519904981063-b0cf448d479e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a colorful test image if download fails
        convert -size 800x600 xc:skyblue \
                -fill red -draw "circle 200,150 250,200" \
                -fill green -draw "rectangle 400,200 600,400" \
                -fill yellow -draw "ellipse 150,450 100,50" \
                -fill black -pointsize 24 -gravity center \
                -annotate +0+200 "COLORIZE ME" landscape_color.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_color.jpg
chmod 644 landscape_color.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_color.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_color.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Colorize task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Go to Colors → Colorize"
echo "   3. In the Colorize dialog:"
echo "      - Adjust the Hue slider to approximately 30° (sepia/warm brown)"
echo "      - Keep Saturation around 50% (default is usually fine)"
echo "      - Keep Lightness around 0 (preserve original brightness)"
echo "   4. Click OK to apply the colorize effect"
echo "   5. The export will be automated after editing"