#!/bin/bash
set -e

echo "=== Setting up grid render task ==="

# Install required packages for verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a suitable image for grid overlay
echo "📥 Downloading base image for grid overlay..."
cd /home/ga/Desktop/
wget -q -O base_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O base_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 xc:lightgray -fill darkblue -pointsize 32 -gravity center -annotate +0+0 "ADD GRID HERE" base_image.jpg
    }
}

# Set proper permissions
chown ga:ga base_image.jpg
chmod 644 base_image.jpg

echo "✅ Base image downloaded to /home/ga/Desktop/base_image.jpg"

echo "🎨 Opening GIMP with the base image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/base_image.jpg > /tmp/gimp_grid.log 2>&1 &"

sleep 3

echo "=== Grid render task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The base image is already open in GIMP"
echo "   2. Go to Filters → Render → Pattern → Grid"
echo "   3. Configure grid parameters:"
echo "      - Set Width (horizontal spacing) to 50-100 pixels"
echo "      - Set Height (vertical spacing) to 50-100 pixels" 
echo "      - Set Line width to 1-3 pixels"
echo "      - Choose a contrasting color (black, white, or gray)"
echo "   4. Use preview to check the grid appearance"
echo "   5. Click OK to apply the grid"
echo "   6. The export will be automated after rendering"