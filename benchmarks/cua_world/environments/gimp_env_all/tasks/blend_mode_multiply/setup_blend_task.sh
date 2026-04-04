#!/bin/bash
set -e

echo "=== Setting up blend mode multiply task ==="

# Install required packages for image processing verification
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy imagemagick

# Download a base landscape photograph
echo "📥 Downloading base landscape image..."
cd /home/ga/Desktop/
wget -q -O base_landscape.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
    echo "❌ Failed to download from primary source, trying alternative..."
    wget -q -O base_landscape.jpg "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80" || {
        echo "❌ All sources failed, using fallback..."
        # Create a simple gradient test image if download fails
        convert -size 800x600 gradient:#87CEEB-#228B22 base_landscape.jpg
    }
}

# Create a warm orange overlay layer (semi-transparent)
echo "🎨 Creating color overlay layer..."
convert -size 800x600 xc:"#FF6600" -alpha set -channel Alpha -evaluate set 70% overlay_orange.png

# Set proper permissions
chown ga:ga base_landscape.jpg overlay_orange.png
chmod 644 base_landscape.jpg overlay_orange.png

echo "✅ Images prepared:"
echo "   - Base landscape: /home/ga/Desktop/base_landscape.jpg"
echo "   - Color overlay: /home/ga/Desktop/overlay_orange.png"

# Create a GIMP script to load both images as layers
cat > /home/ga/Desktop/load_layers.scm << 'EOF'
; Script-Fu to load both images as layers
(define (load-two-layer-composition base-img overlay-img output-xcf)
  (let* ((image (car (gimp-file-load RUN-NONINTERACTIVE base-img base-img)))
         (base-layer (car (gimp-image-get-active-layer image)))
         (overlay-layer 0))
    
    ; Load overlay as new layer
    (set! overlay-layer (car (gimp-file-load-layer RUN-NONINTERACTIVE image overlay-img)))
    (gimp-image-insert-layer image overlay-layer 0 0)
    
    ; Set overlay layer name and ensure it's on top
    (gimp-item-set-name overlay-layer "Color Overlay")
    (gimp-item-set-name base-layer "Background")
    
    ; Make sure overlay is active and in Normal mode (default)
    (gimp-image-set-active-layer image overlay-layer)
    (gimp-layer-set-mode overlay-layer LAYER-MODE-NORMAL)
    
    ; Save as XCF to preserve layers
    (gimp-xcf-save RUN-NONINTERACTIVE image 0 output-xcf output-xcf)
    
    ; Return image ID
    image))

; Execute the function
(let ((img (load-two-layer-composition "/home/ga/Desktop/base_landscape.jpg" 
                                      "/home/ga/Desktop/overlay_orange.png"
                                      "/home/ga/Desktop/blend_composition.xcf")))
  (gimp-quit 0))
EOF

chown ga:ga /home/ga/Desktop/load_layers.scm

echo "🔧 Creating two-layer composition using GIMP..."
# Run the Script-Fu to create the layered composition
su - ga -c "DISPLAY=:1 gimp -i -b '(load \"/home/ga/Desktop/load_layers.scm\")' -b '(gimp-quit 0)'" || {
    echo "⚠️ Script-Fu failed, using alternative method..."
    # Fallback: just copy the base image as our starting point
    cp base_landscape.jpg blend_composition.xcf 2>/dev/null || true
}

sleep 2

echo "🎨 Opening GIMP with the layered composition..."
# Launch GIMP with the layered composition (or base image if script failed)
if [ -f "/home/ga/Desktop/blend_composition.xcf" ]; then
    su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/blend_composition.xcf > /tmp/gimp_blend.log 2>&1 &"
else
    echo "🔄 Opening individual files as layers manually..."
    su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/base_landscape.jpg > /tmp/gimp_blend.log 2>&1 &"
fi

sleep 4

echo "=== Blend mode task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. A two-layer composition should be open in GIMP"
echo "   2. If only base image is open, add overlay as new layer:"
echo "      - File → Open as Layers → select overlay_orange.png"
echo "   3. Ensure the top layer (overlay) is selected in Layers panel"
echo "   4. Find the Layers panel (usually docked on right side)"
echo "   5. Locate the blend mode dropdown (shows 'Normal' currently)"
echo "   6. Click the dropdown and select 'Multiply'"
echo "   7. Observe the darkening effect on the image"
echo "   8. Both PNG and XCF exports will be automated"