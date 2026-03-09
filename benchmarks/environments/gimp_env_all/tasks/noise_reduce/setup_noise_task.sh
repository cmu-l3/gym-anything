#!/bin/bash
set -e

echo "=== Setting up noise reduction task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy imagemagick

# Download noisy image or create one with artificial noise
echo "📥 Downloading/creating noisy image..."
cd /home/ga/Desktop/
wget -q -O noisy_photo.jpg "https://images.unsplash.com/photo-1519904981063-b0cf448d479e?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=60" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O noisy_photo.jpg "https://images.unsplash.com/photo-1542744173-8e7e53415bb0?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=60" || {
        echo "❌ All sources failed, creating artificial noisy image..."
        # Create a test image with noise if download fails
        convert -size 600x400 xc:lightblue -fill navy -pointsize 24 -gravity center -annotate +0+0 "REDUCE NOISE" -noise Gaussian temp_clean.jpg
        convert temp_clean.jpg -noise Uniform noisy_photo.jpg
        rm -f temp_clean.jpg
    }
}

# Add additional noise to ensure visible graininess for the task
echo "🔧 Enhancing noise visibility for task..."
convert noisy_photo.jpg -noise Gaussian -noise Salt-and-pepper noisy_photo.jpg || {
    echo "⚠️ Could not add extra noise, using original image"
}

# Set proper permissions
chown ga:ga noisy_photo.jpg
chmod 644 noisy_photo.jpg

echo "✅ Noisy image prepared at /home/ga/Desktop/noisy_photo.jpg"

echo "🎨 Opening GIMP with the noisy image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/noisy_photo.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Noise reduction task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The noisy photograph is already open in GIMP"
echo "   2. Go to Filters → Enhance → Despeckle"
echo "   3. The default settings should work well for most cases"
echo "   4. Preview the effect to ensure noise is reduced while preserving details"
echo "   5. Click OK to apply the noise reduction filter"
echo "   6. The export will be automated after editing"