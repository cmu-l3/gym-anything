#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up text overlay task ==="

# Download a beautiful landscape image for text overlay
echo "📥 Downloading landscape image..."
wget -q "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&h=600&fit=crop&crop=center" \
     -O "/home/ga/Desktop/landscape_image.jpg"

# Set proper ownership and permissions
chown ga:ga "/home/ga/Desktop/landscape_image.jpg"
chmod 644 "/home/ga/Desktop/landscape_image.jpg"

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_image.jpg"

# Wait a moment for file system sync
sleep 1

# Open GIMP with the landscape image
echo "🎨 Opening GIMP with the landscape image..."
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_image.jpg > /tmp/gimp_text.log 2>&1 &"

# Wait for GIMP to start and load the image
sleep 5

echo "=== Text overlay task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Select the Text Tool (T key or from toolbox)"
echo "   3. Click on the lower center area of the image"
echo "   4. Type 'SUMMER VIBES' as the text"
echo "   5. Increase font size to make it large (try 48-72pt)"
echo "   6. Set text color to white"
echo "   7. Make text bold if possible"
echo "   8. Add a black drop shadow or stroke for readability"
echo "   9. Position text nicely in lower center area"
echo "   10. The export will be automated after editing"
