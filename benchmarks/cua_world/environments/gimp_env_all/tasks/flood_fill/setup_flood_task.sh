#!/bin/bash
set -e

echo "=== Setting up flood fill task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy imagemagick

# Create a geometric shapes image for flood fill testing
echo "🎨 Creating geometric shapes image..."
cd /home/ga/Desktop/

# Create image with distinct colored geometric shapes including a white circle to fill
convert -size 800x600 xc:lightgray \
  -fill blue -draw "rectangle 100,100 250,250" \
  -fill green -draw "polygon 300,100 450,100 375,250" \
  -fill yellow -draw "rectangle 500,100 650,250" \
  -fill white -draw "circle 400,400 400,300" \
  -fill red -draw "rectangle 100,350 250,500" \
  -fill purple -draw "polygon 500,350 650,350 575,500" \
  -stroke black -strokewidth 3 \
  -fill none -draw "rectangle 100,100 250,250" \
  -draw "polygon 300,100 450,100 375,250" \
  -draw "rectangle 500,100 650,250" \
  -draw "circle 400,400 400,300" \
  -draw "rectangle 100,350 250,500" \
  -draw "polygon 500,350 650,350 575,500" \
  geometric_shapes.png

# Fallback: download a simple shapes image if creation fails
if [ ! -f "geometric_shapes.png" ]; then
    echo "📥 Downloading shapes image as fallback..."
    wget -q -O geometric_shapes.png "https://via.placeholder.com/800x600/lightgray/000000?text=SHAPES" || {
        echo "❌ Fallback failed, creating minimal test image..."
        convert -size 800x600 xc:lightgray -fill white -draw "circle 400,300 400,200" geometric_shapes.png
    }
fi

# Set proper permissions
chown ga:ga geometric_shapes.png
chmod 644 geometric_shapes.png

echo "✅ Geometric shapes image created at /home/ga/Desktop/geometric_shapes.png"

echo "🎨 Opening GIMP with the geometric shapes image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/geometric_shapes.png > /tmp/gimp_flood.log 2>&1 &"

sleep 3

echo "🎯 Focusing GIMP window..."
wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
echo "GIMP window ID: $wid"
su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
sleep 1
# Now make the window full screen
su - ga -c "DISPLAY=:1 xdotool key --delay 200 F11" || true
sleep 1

echo "=== Flood fill task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The geometric shapes image is already open in GIMP"
echo "   2. Select the Bucket Fill tool (Shift+B or from toolbox)"
echo "   3. Click on the foreground color to choose a bright color (like red or blue)"
echo "   4. Click on the white circle in the center to fill it"
echo "   5. The fill should change the white circle to your chosen color"
echo "   6. The export will be automated after editing"