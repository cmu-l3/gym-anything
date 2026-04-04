#!/bin/bash
set -e

echo "=== Setting up offset wrap-around task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with clear pattern/texture for offset testing
echo "📥 Downloading pattern texture image..."
cd /home/ga/Desktop/
wget -q -O pattern_texture.jpg "https://images.unsplash.com/photo-1557804506-669a67965ba0?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O pattern_texture.jpg "https://images.unsplash.com/photo-1578662996442-48f60103fc96?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test pattern if download fails
        convert -size 400x300 -define gradient:direction=NorthWest gradient:red-blue -swirl 50 pattern_texture.jpg
    }
}

# Set proper permissions
chown ga:ga pattern_texture.jpg
chmod 644 pattern_texture.jpg

echo "✅ Pattern texture image downloaded to /home/ga/Desktop/pattern_texture.jpg"

echo "🎨 Opening GIMP with the pattern texture image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/pattern_texture.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Offset wrap-around task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The pattern texture image is already open in GIMP"
echo "   2. Go to Layer → Transform → Offset (or similar menu path)"
echo "   3. In the Offset dialog:"
echo "      - Set X offset to 100 pixels"
echo "      - Set Y offset to 80 pixels"
echo "      - Make sure 'Wrap around' mode is selected (not background fill)"
echo "   4. Click OK to apply the offset"
echo "   5. The export will be automated after editing"