#!/bin/bash
set -e

echo "=== Setting up soft glow effect task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy

# Download portrait image suitable for soft glow effect
echo "📥 Downloading portrait image..."
cd /home/ga/Desktop/
wget -q -O portrait_softglow.jpg "https://images.unsplash.com/photo-1534528741775-53994a69daeb?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O portrait_softglow.jpg "https://images.unsplash.com/photo-1531123897727-8f129e1688ce?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image with bright areas if download fails
        convert -size 800x600 xc:lightgray -fill white -draw "circle 400,300 400,200" -fill black -pointsize 24 -gravity center -annotate +0+200 "APPLY SOFT GLOW" portrait_softglow.jpg
    }
}

# Set proper permissions
chown ga:ga portrait_softglow.jpg
chmod 644 portrait_softglow.jpg

echo "✅ Portrait image downloaded to /home/ga/Desktop/portrait_softglow.jpg"

echo "🎨 Opening GIMP with the portrait image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/portrait_softglow.jpg > /tmp/gimp_softglow.log 2>&1 &"

sleep 3

echo "=== Soft glow task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The portrait image is already open in GIMP"
echo "   2. Go to Filters → Light and Shadow → Softglow (or Filters → Artistic → Softglow)"
echo "   3. The Soft Glow dialog will open with preview"
echo "   4. Default settings usually work well, but you can adjust:"
echo "      - Glow radius (10-20 typical)"
echo "      - Brightness (0.70-0.95 typical)"
echo "   5. Click OK to apply the effect"
echo "   6. Wait for processing to complete"
echo "   7. The export will be automated after applying the effect"