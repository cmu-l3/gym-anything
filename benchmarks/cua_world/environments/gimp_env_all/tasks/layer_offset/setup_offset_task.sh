#!/bin/bash
set -e

echo "=== Setting up layer offset task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download texture/pattern image suitable for offset testing
echo "📥 Downloading texture pattern image..."
cd /home/ga/Desktop/
wget -q -O texture_pattern.jpg "https://images.unsplash.com/photo-1557804506-669a67965ba0?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O texture_pattern.jpg "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test pattern if download fails
        convert -size 512x512 pattern:checkerboard -scale 64x64 -scale 512x512 texture_pattern.jpg
    }
}

# Set proper permissions
chown ga:ga texture_pattern.jpg
chmod 644 texture_pattern.jpg

echo "✅ Texture pattern downloaded to /home/ga/Desktop/texture_pattern.jpg"

echo "🎨 Opening GIMP with the texture pattern..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/texture_pattern.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Layer offset task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The texture pattern image is already open in GIMP"
echo "   2. Go to Layer → Transform → Offset"
echo "   3. Set X (horizontal) offset to half the image width (e.g., 256 for 512px width)"
echo "   4. Optionally set Y (vertical) offset to half the height"
echo "   5. Make sure 'Wrap around' mode is selected (not 'Fill with background')"
echo "   6. Click OK to apply the offset"
echo "   7. The export will be automated after editing"