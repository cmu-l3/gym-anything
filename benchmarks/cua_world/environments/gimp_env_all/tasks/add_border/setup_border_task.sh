#!/bin/bash
set -e

echo "=== Setting up add border task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download image suitable for adding borders
echo "📥 Downloading sample image for border task..."
cd /home/ga/Desktop/
wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 600x400 xc:lightblue -fill darkblue -pointsize 36 -gravity center -annotate +0+0 "ADD BORDER TO ME" sample_image.jpg
    }
}

# Set proper permissions
chown ga:ga sample_image.jpg
chmod 644 sample_image.jpg

echo "✅ Sample image downloaded to /home/ga/Desktop/sample_image.jpg"

echo "🎨 Opening GIMP with the sample image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/sample_image.jpg > /tmp/gimp_task.log 2>&1 &"

# Wait for GIMP's window to actually render with the image loaded before the
# episode starts. A blind `sleep 3` races GIMP's launch (it is heavy and often
# needs longer); if the first observation lands on a bare desktop, the task
# premise ("the image is already open in GIMP") is broken and the agent cannot
# recover. Poll for the main window whose title carries the image filename
# (this appears only once the image is loaded, i.e. past the splash screen).
echo "⏳ Waiting for GIMP to open the image..."
gimp_ready=0
for _ in $(seq 1 60); do
    if su - ga -c "DISPLAY=:1 xdotool search --name 'sample_image.*GIMP'" >/dev/null 2>&1; then
        gimp_ready=1
        break
    fi
    sleep 1
done
if [ "$gimp_ready" -eq 1 ]; then
    echo "✅ GIMP window is up with the image loaded"
else
    echo "⚠️ GIMP window not detected after 60s; continuing anyway"
fi
# Brief settle so the canvas and menu bar finish drawing.
sleep 2

echo "=== Add border task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The sample image is already open in GIMP"
echo "   2. Go to Filters → Decor → Border"
echo "   3. Configure border size (e.g., 25 pixels)"
echo "   4. Choose border color (e.g., black or white)"
echo "   5. Click OK to apply the border effect"
echo "   6. The export will be automated after editing"