#!/bin/bash
set -e

echo "=== Setting up newsprint halftone task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a continuous-tone photograph suitable for halftone effect
echo "📥 Downloading photograph for newsprint effect..."
cd /home/ga/Desktop/
wget -q -O photo_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_image.jpg "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with gradients if download fails
        convert -size 800x600 gradient:white-black -swirl 50 photo_image.jpg
    }
}

# Set proper permissions
chown ga:ga photo_image.jpg
chmod 644 photo_image.jpg

echo "✅ Photograph downloaded to /home/ga/Desktop/photo_image.jpg"

echo "🎨 Opening GIMP with the photograph..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Newsprint halftone task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The photograph is already open in GIMP"
echo "   2. Go to Filters → Distorts → Newsprint"
echo "   3. The Newsprint dialog will open with preview"
echo "   4. The default settings should work well for typical halftone effect"
echo "   5. Click OK to apply the newsprint transformation"
echo "   6. Observe that continuous tones become dot patterns"
echo "   7. The export will be automated after applying the effect"