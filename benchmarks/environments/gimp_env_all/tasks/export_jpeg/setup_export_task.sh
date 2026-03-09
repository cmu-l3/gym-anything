#!/bin/bash
set -e

echo "=== Setting up JPEG export task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download a high-quality PNG photograph suitable for JPEG conversion
echo "📥 Downloading PNG photograph..."
cd /home/ga/Desktop/
wget -q -O photo_image.png "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=1000&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O photo_image.png "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 gradient:blue-yellow -quality 100 photo_image.png 2>/dev/null || {
            # Even simpler fallback if ImageMagick isn't available
            echo "Creating minimal test image..."
            python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 600), color='lightblue')
draw = ImageDraw.Draw(img)
draw.rectangle([100, 100, 700, 500], fill='orange', outline='black', width=3)
draw.text((400, 300), 'EXPORT AS JPEG', fill='black', anchor='mm')
img.save('photo_image.png', 'PNG')
"
        }
    }
}

# Set proper permissions
chown ga:ga photo_image.png
chmod 644 photo_image.png

echo "✅ PNG photograph downloaded to /home/ga/Desktop/photo_image.png"

echo "🎨 Opening GIMP with the PNG image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/photo_image.png > /tmp/gimp_export.log 2>&1 &"

sleep 3

echo "=== JPEG export task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The PNG photograph is already open in GIMP"
echo "   2. Go to File → Export As (or File → Export)"
echo "   3. Change the filename to end with .jpg (e.g., 'exported_photo.jpg')"
echo "   4. Click Export to proceed to JPEG options"
echo "   5. In the JPEG export dialog:"
echo "      - Set Quality to around 85 (good balance for web use)"
echo "      - Keep other settings as default"
echo "   6. Click Export to complete the conversion"
echo "   7. The verifier will check the exported JPEG file"