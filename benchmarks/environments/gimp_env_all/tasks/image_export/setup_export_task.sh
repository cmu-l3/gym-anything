#!/bin/bash
set -e

echo "=== Setting up image export task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy file

# Download landscape image for export task
echo "📥 Downloading landscape image..."
cd /home/ga/Desktop/
wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O landscape_image.jpg "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple test image if download fails
        convert -size 800x600 gradient:blue-green -pointsize 36 -fill white -gravity center -annotate +0+0 "EXPORT AS PNG" landscape_image.jpg
    }
}

# Set proper permissions
chown ga:ga landscape_image.jpg
chmod 644 landscape_image.jpg

echo "✅ Landscape image downloaded to /home/ga/Desktop/landscape_image.jpg"

# Remove any pre-existing target files to ensure clean test environment
echo "🧹 Cleaning up any pre-existing target files..."
rm -f /home/ga/Desktop/landscape_final.png
rm -f /home/ga/Desktop/landscape_final.PNG  
rm -f /home/ga/Desktop/landscape_final.jpg
rm -f /home/ga/Desktop/landscape_final.jpeg
rm -f /home/ga/Desktop/*landscape*final*

echo "✅ Target files cleaned up"

echo "🎨 Opening GIMP with the landscape image..."
# Launch GIMP with the image
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/landscape_image.jpg > /tmp/gimp_export.log 2>&1 &"

sleep 3

echo "=== Image export task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The landscape image is already open in GIMP"
echo "   2. Go to File → Export As (or use Ctrl+Shift+E)"
echo "   3. Enter filename: 'landscape_final.png'"
echo "   4. Ensure PNG format is selected" 
echo "   5. Click Export to save the file"
echo "   6. Handle any PNG export options dialog that appears"
echo "   7. Verify the file was saved successfully"