#!/bin/bash
set -e

echo "=== Setting up new image creation task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq python3-pil python3-numpy

# Clean up any existing files that might interfere
cd /home/ga/Desktop/
rm -f new_blank_image.* blank_image.* new_image.* || true

# Set proper permissions for desktop directory
chown -R ga:ga /home/ga/Desktop/
chmod 755 /home/ga/Desktop/

echo "🎨 Opening GIMP for new image creation..."
# Launch GIMP without any pre-loaded image
su - ga -c "DISPLAY=:1 gimp > /tmp/gimp_new.log 2>&1 &"

sleep 3

echo "=== New image creation task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. GIMP is now open with no images loaded"
echo "   2. Go to File → New to create a new image"
echo "   3. Set the width to 640 pixels"
echo "   4. Set the height to 480 pixels" 
echo "   5. Set the background fill to White"
echo "   6. Click OK to create the new image"
echo "   7. The export will be automated after creation"