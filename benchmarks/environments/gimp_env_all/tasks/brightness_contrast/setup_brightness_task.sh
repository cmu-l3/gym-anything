#!/bin/bash
set -e

echo "=== Setting up brightness/contrast adjustment task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download an underexposed landscape image
echo "📥 Downloading underexposed landscape image..."
cd /home/ga/Desktop/
wget -q -O underexposed_landscape.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=60" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O underexposed_landscape.jpg "https://images.unsplash.com/photo-1518837695005-2083093ee35b?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=60" || {
        echo "❌ All sources failed, using fallback..."
        # Create a dark test image if download fails
        convert -size 800x600 xc:"rgb(60,60,70)" -fill "rgb(40,40,50)" -draw "rectangle 100,100 700,500" -fill black -pointsize 24 -gravity center -annotate +0+0 "ENHANCE THIS IMAGE" underexposed_landscape.jpg
    }
}

# Set proper permissions
chown ga:ga underexposed_landscape.jpg
chmod 644 underexposed_landscape.jpg

echo "✅ Underexposed landscape image downloaded to /home/ga/Desktop/underexposed_landscape.jpg"

echo "🎨 Opening GIMP with the underexposed image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/underexposed_landscape.jpg > /tmp/gimp_task.log 2>&1 &"

sleep 3

echo "=== Brightness/contrast adjustment task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The underexposed landscape image is already open in GIMP"
echo "   2. Go to Colors → Brightness-Contrast"
echo "   3. In the dialog that opens:"
echo "      - Increase Brightness slider (try +20 to +40)"
echo "      - Increase Contrast slider (try +15 to +35)"
echo "      - Use the preview to see the changes"
echo "   4. Click OK to apply the adjustments"
echo "   5. The export will be automated after editing"