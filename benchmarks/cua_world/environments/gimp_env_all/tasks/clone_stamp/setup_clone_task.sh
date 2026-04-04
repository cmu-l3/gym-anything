#!/bin/bash
set -e

echo "=== Setting up clone tool task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy imagemagick

# Download image with clear source texture and target area to remove
echo "📥 Downloading landscape image with object to remove..."
cd /home/ga/Desktop/
wget -q -O landscape_with_object.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_with_object.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, creating fallback..."
        # Create a simple test image with grass texture and object to remove if download fails
        convert -size 800x600 \
            \( -size 800x600 xc:green -noise 3 \) \
            \( -size 100x100 xc:red -draw "rectangle 350,250 450,350" \) \
            -composite landscape_with_object.jpg
    }
}

echo "🎯 Adding red marker to indicate target area for cloning..."
# Add a small red marker to indicate what should be removed/cloned over
convert landscape_with_object.jpg \
    -fill red -stroke red -strokewidth 3 \
    -draw "rectangle 380,280 420,320" \
    landscape_with_object.jpg

# Set proper permissions
chown ga:ga landscape_with_object.jpg
chmod 644 landscape_with_object.jpg

echo "✅ Landscape image with target marker downloaded to /home/ga/Desktop/landscape_with_object.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_with_object.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Clone tool task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Select the Clone Tool (C key or from toolbox)"
echo "   3. Hold Ctrl and click on suitable source texture area"
echo "   4. Paint over the red-marked target area to clone texture"
echo "   5. Continue painting until the red area is completely covered"
echo "   6. Use surrounding grass/texture as source for natural results"
echo "   7. The export will be automated after editing"