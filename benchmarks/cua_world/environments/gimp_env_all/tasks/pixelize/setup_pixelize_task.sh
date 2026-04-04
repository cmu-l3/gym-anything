#!/bin/bash
set -e

echo "=== Setting up pixelize task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with good detail for pixelization effect
echo "📥 Downloading image for pixelization..."
cd /home/ga/Desktop/
wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O sample_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a test image with gradients if download fails
        convert -size 800x600 gradient:blue-yellow -swirl 60 sample_image.jpg
    }
}

# Set proper permissions
chown ga:ga sample_image.jpg
chmod 644 sample_image.jpg

echo "✅ Sample image downloaded to /home/ga/Desktop/sample_image.jpg"

echo "🎨 Opening GIMP with the sample image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/sample_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Pixelize task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The sample image is already open in GIMP"
echo "   2. Go to Filters → Blur → Pixelize"
echo "   3. Set pixel width and height to 10 pixels"
echo "   4. Apply the filter by clicking OK"
echo "   5. The export will be automated after editing"