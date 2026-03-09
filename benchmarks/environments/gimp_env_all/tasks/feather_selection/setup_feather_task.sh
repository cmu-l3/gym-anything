#!/bin/bash
set -e

echo "=== Setting up feather selection task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download landscape image suitable for feathering demonstration
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_feather.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_feather.jpg "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple gradient background if download fails
        convert -size 800x600 gradient:blue-green landscape_feather.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_feather.jpg
chmod 644 landscape_feather.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_feather.jpg"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_feather.jpg > /tmp/gimp_feather.log 2>&1 &"

sleep 3

echo "=== Feather selection task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Use Rectangle Select Tool (R key or from toolbox)"
echo "   3. Create a rectangular selection in the center (about 40% of image size)"
echo "   4. Go to Select → Feather"
echo "   5. Set feather radius to 20 pixels and click OK"
echo "   6. Set foreground color to white (click color swatch)"
echo "   7. Fill selection with Edit → Fill with FG Color (or Ctrl+;)"
echo "   8. Go to Select → None to deselect and see result"
echo "   9. The export will be automated after editing"