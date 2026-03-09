#!/bin/bash
set -e

echo "=== Setting up add noise task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download image with smooth areas ideal for noise testing
echo "📥 Downloading clean image for noise addition..."
cd /home/ga/Desktop/
wget -q -O clean_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O clean_image.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple gradient image if download fails
        convert -size 800x600 gradient:lightblue-white clean_image.jpg
    }
}

# Set proper permissions
chown ga:ga clean_image.jpg
chmod 644 clean_image.jpg

echo "✅ Clean image downloaded to /home/ga/Desktop/clean_image.jpg"

echo "🎨 Opening GIMP with the clean image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/clean_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Add noise task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The clean image is already open in GIMP"
echo "   2. Go to Filters → Noise → RGB Noise"
echo "   3. In the RGB Noise dialog:"
echo "      - Set noise amount between 0.20 and 0.40"
echo "      - Keep 'Independent RGB' checked"
echo "      - Use preview to see the effect"
echo "   4. Click OK to apply the noise filter"
echo "   5. The export will be automated after editing"