#!/bin/bash
set -e

echo "=== Setting up canvas resize task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a landscape image (800x600) for canvas expansion
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_canvas.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&h=600&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_canvas.jpg "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&h=600&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightblue -fill darkblue -pointsize 36 -gravity center -annotate +0+0 "EXPAND CANVAS\nTO 1000x800" landscape_canvas.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_canvas.jpg
chmod 644 landscape_canvas.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_canvas.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_canvas.jpg > /tmp/gimp_canvas.log 2>&1 &"

sleep 3

echo "=== Canvas resize task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Go to Image → Canvas Size in the menu"
echo "   3. In the Canvas Size dialog:"
echo "      - Change width to 1000 pixels"
echo "      - Change height to 800 pixels"
echo "      - Make sure content stays centered (anchor in middle)"
echo "   4. Click OK or Resize to apply the canvas expansion"
echo "   5. The export will be automated after editing"