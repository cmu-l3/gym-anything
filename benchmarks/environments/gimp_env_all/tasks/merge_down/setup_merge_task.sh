#!/bin/bash
set -e

echo "=== Setting up merge down layers task ==="

# Install required packages for image processing and XCF handling
apt-get update -qq
apt-get install -y -qq wget python3-pil python3-numpy python3-scipy imagemagick

# Create a multi-layer composition
echo "🎨 Creating multi-layer composition..."
cd /home/ga/Desktop/

# Create background layer (blue gradient)
convert -size 400x300 gradient:blue-lightblue background.png

# Create middle layer (red circle)
convert -size 400x300 xc:transparent -fill red -draw "circle 200,150 250,200" middle_layer.png

# Create top layer (yellow text)
convert -size 400x300 xc:transparent -fill yellow -pointsize 36 -gravity center -annotate +0-50 "MERGE ME" top_layer.png

# Combine into XCF using GIMP batch mode (create the multi-layer file)
echo "📁 Creating multi-layer XCF file..."

# Create a GIMP script to build the XCF
cat > create_layers.scm << 'EOF'
(let* ((image (car (gimp-image-new 400 300 RGB)))
       (bg-layer (car (gimp-file-load-layer RUN-NONINTERACTIVE image "background.png")))
       (mid-layer (car (gimp-file-load-layer RUN-NONINTERACTIVE image "middle_layer.png")))
       (top-layer (car (gimp-file-load-layer RUN-NONINTERACTIVE image "top_layer.png"))))
  
  ; Add layers to image (in reverse order - GIMP adds at top)
  (gimp-image-insert-layer image bg-layer 0 -1)
  (gimp-image-insert-layer image mid-layer 0 0)
  (gimp-image-insert-layer image top-layer 0 0)
  
  ; Set layer names
  (gimp-item-set-name bg-layer "Background")
  (gimp-item-set-name mid-layer "Circle")
  (gimp-item-set-name top-layer "Text")
  
  ; Save as XCF
  (gimp-xcf-save RUN-NONINTERACTIVE image 0 "multi_layer_composition.xcf" "multi_layer_composition.xcf")
  
  ; Also save flattened version for comparison
  (set! flattened-image (car (gimp-image-flatten image)))
  (gimp-file-save RUN-NONINTERACTIVE image flattened-image "original_flattened.png" "original_flattened.png")
  
  (gimp-quit 0))
EOF

# Run GIMP in batch mode to create the XCF
echo "🔧 Running GIMP batch process to create XCF..."
gimp -i -b '(load "create_layers.scm")' -b '(gimp-quit 0)' || {
    echo "❌ GIMP batch failed, creating simple XCF manually..."
    # Fallback: create a simpler version
    convert background.png middle_layer.png top_layer.png -flatten fallback_composition.png
    cp fallback_composition.png multi_layer_composition.xcf
}

# Clean up temporary files
rm -f background.png middle_layer.png top_layer.png create_layers.scm

# Set proper permissions
chown ga:ga multi_layer_composition.xcf original_flattened.png
chmod 644 multi_layer_composition.xcf original_flattened.png

echo "✅ Multi-layer XCF created at /home/ga/Desktop/multi_layer_composition.xcf"

echo "🎨 Opening GIMP with the multi-layer composition..."
# Launch GIMP with the XCF file
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/multi_layer_composition.xcf > /tmp/gimp_merge.log 2>&1 &"

sleep 3

echo "=== Merge down task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. The multi-layer composition is already open in GIMP"
echo "   2. Open the Layers panel if not visible (Windows → Dockable Dialogs → Layers)"
echo "   3. You should see 3 layers: Text, Circle, Background"
echo "   4. Select the 'Text' layer (top layer)"
echo "   5. Right-click and select 'Merge Down' OR use Layer → Merge Down"
echo "   6. This will merge the Text layer with the Circle layer below it"
echo "   7. The export will be automated after merging"