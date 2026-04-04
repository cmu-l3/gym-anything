#!/bin/bash
set -e

echo "=== Setting up color replacement task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with prominent red color
echo "📥 Downloading red car image..."
cd /home/ga/Desktop/
wget -q -O red_car_image.jpg "https://images.unsplash.com/photo-1583121274602-3e2820c69888?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O red_car_image.jpg "https://images.unsplash.com/photo-1552519507-da3b142c6e3d?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with red elements if download fails
        convert -size 800x600 xc:white -fill red -draw "rectangle 200,200 600,400" -fill black -pointsize 24 -gravity center -annotate +0+100 "CHANGE RED TO BLUE" red_car_image.jpg
    }
}

# Set proper permissions
chown ga:ga red_car_image.jpg
chmod 644 red_car_image.jpg

echo "✅ Red car image downloaded to /home/ga/Desktop/red_car_image.jpg"

echo "🎨 Opening GIMP with the red car image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/red_car_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Color replacement task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The red car image is already open in GIMP"
echo "   2. Go to Select → By Color Tool (or use Shift+O)"
echo "   3. Click on the red parts of the car to select them"
echo "   4. Adjust threshold if needed to select all red areas"
echo "   5. Go to Colors → Hue-Saturation"
echo "   6. In the Hue-Saturation dialog:"
echo "      - Make sure 'Reds' channel is selected"
echo "      - Move the Hue slider to change red to blue (~-120)"
echo "   7. Click OK to apply the color change"
echo "   8. Go to Select → None to deselect"
echo "   9. The export will be automated after editing"
