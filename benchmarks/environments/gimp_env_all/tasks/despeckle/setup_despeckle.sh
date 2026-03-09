#!/bin/bash
set -e

echo "=== Setting up despeckle (noise reduction) task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy imagemagick

# Download or create a noisy image for despeckle testing
echo "📥 Creating noisy image for despeckle task..."
cd /home/ga/Desktop/

# Try to download a good base image first
wget -q -O base_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download base image, creating synthetic image..."
    # Create a simple base image if download fails
    convert -size 600x400 gradient:blue-white base_image.jpg
}

# Add noise to create a speckled image using ImageMagick
echo "🔧 Adding noise to create test image..."
convert base_image.jpg -attenuate 0.3 +noise Random noisy_image.jpg || {
    echo "⚠️ ImageMagick noise failed, using alternative method..."
    # Fallback: create a simple noisy pattern
    convert -size 600x400 xc:lightgray \( +noise Random -blur 0x0.5 \) -compose multiply -composite noisy_image.jpg
}

# Clean up temporary file
rm -f base_image.jpg

# Set proper permissions
chown ga:ga noisy_image.jpg
chmod 644 noisy_image.jpg

echo "✅ Noisy image created at /home/ga/Desktop/noisy_image.jpg"

echo "🎨 Opening GIMP with the noisy image..."
# Launch GIMP with the noisy image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/noisy_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Despeckle task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The noisy image is already open in GIMP"
echo "   2. Go to Filters → Enhance → Despeckle"
echo "   3. Review the preview to see noise reduction effect"
echo "   4. Adjust settings if needed (radius, threshold values)"
echo "   5. Click OK to apply the despeckle filter"
echo "   6. The export will be automated after filtering"