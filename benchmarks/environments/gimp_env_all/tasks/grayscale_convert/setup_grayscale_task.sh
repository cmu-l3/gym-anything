#!/bin/bash
set -e

echo "=== Setting up grayscale conversion task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download a colorful flower image
echo "📥 Downloading colorful flower image..."
cd /home/ga/Desktop/
wget -q -O flower_color.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O flower_color.jpg "https://images.unsplash.com/photo-1518709268805-4e9042af2176?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple colorful test image if download fails
        convert -size 800x600 gradient:red-blue -swirl 60 flower_color.jpg
    }
}

# Set proper permissions
chown ga:ga flower_color.jpg
chmod 644 flower_color.jpg

echo "✅ Colorful flower image downloaded to /home/ga/Desktop/flower_color.jpg"

echo "🎨 Opening GIMP with the flower image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/flower_color.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Grayscale conversion task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The colorful flower image is already open in GIMP"
echo "   2. Go to Image → Mode → Grayscale in the menu"
echo "   3. If a confirmation dialog appears, click 'Convert' or 'OK'"
echo "   4. The image should now appear in black and white"
echo "   5. The export will be automated after conversion"