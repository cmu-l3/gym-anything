#!/bin/bash
set -e

echo "=== Setting up RGB noise task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download clean, smooth image suitable for noise detection
echo "📥 Downloading clean portrait image..."
cd /home/ga/Desktop/
wget -q -O clean_portrait.jpg "https://images.unsplash.com/photo-1494790108755-2616b612b786?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=687&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O clean_portrait.jpg "https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?ixlib=rb-4.0.3&auto=format&fit=crop&w=688&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple clean gradient image if download fails
        convert -size 800x600 -define gradient:direction=NorthWest gradient:lightblue-white clean_portrait.jpg
    }
}

# Set proper permissions
chown ga:ga clean_portrait.jpg
chmod 644 clean_portrait.jpg

echo "✅ Clean portrait image downloaded to /home/ga/Desktop/clean_portrait.jpg"

echo "🎨 Opening GIMP with the clean image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/clean_portrait.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== RGB noise task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The clean portrait image is already open in GIMP"
echo "   2. Go to Filters → Noise → RGB Noise"
echo "   3. In the RGB Noise dialog:"
echo "      - Adjust the noise amount sliders (try 0.20-0.40 range)"
echo "      - Optionally enable 'Independent RGB' for different channel amounts"
echo "      - Click OK to apply the noise"
echo "   4. The export will be automated after editing"