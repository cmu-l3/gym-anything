#!/bin/bash
set -e

echo "=== Setting up auto levels enhancement task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy

# Download an underexposed image for auto levels enhancement
echo "📥 Downloading underexposed image..."
cd /home/ga/Desktop/
wget -q -O underexposed_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=60" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O underexposed_image.jpg "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=60" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple underexposed test image if download fails
        convert -size 800x600 xc:"rgb(40,40,40)" -fill "rgb(80,80,80)" -draw "rectangle 200,150 600,450" -fill white -pointsize 24 -gravity center -annotate +0+100 "ENHANCE ME" underexposed_image.jpg
    }
}

# Set proper permissions
chown ga:ga underexposed_image.jpg
chmod 644 underexposed_image.jpg

echo "✅ Underexposed image downloaded to /home/ga/Desktop/underexposed_image.jpg"

echo "🎨 Opening GIMP with the underexposed image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/underexposed_image.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Auto levels task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The underexposed image is already open in GIMP"
echo "   2. Go to Colors → Auto → Normalize (or similar auto enhancement)"
echo "   3. The auto levels will apply immediately"
echo "   4. Verify the image looks brighter and has better contrast"
echo "   5. The export will be automated after enhancement"