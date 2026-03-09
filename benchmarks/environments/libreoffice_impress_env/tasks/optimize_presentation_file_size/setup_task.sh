#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Optimize Presentation File Size Task ==="

DATA_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$DATA_DIR"
ASSET_DIR="/tmp/heavy_assets"
mkdir -p "$ASSET_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Download real high-res images (Wikimedia Commons / NASA)
# We use curl with retry and fail-fast. If these fail, we generate noise images as fallback.
echo "Acquiring high-resolution assets..."

declare -A IMAGES
IMAGES=(
    ["img1.jpg"]="https://upload.wikimedia.org/wikipedia/commons/e/e0/Carina_Nebula.jpg"
    ["img2.jpg"]="https://upload.wikimedia.org/wikipedia/commons/b/b2/Whirlpool_Galaxy.jpg"
    ["img3.jpg"]="https://upload.wikimedia.org/wikipedia/commons/3/36/The_Great_Wall_of_China_at_Jinshanling-edit.jpg"
    ["img4.jpg"]="https://upload.wikimedia.org/wikipedia/commons/c/c2/Port_of_Hong_Kong.jpg"
    ["img5.jpg"]="https://upload.wikimedia.org/wikipedia/commons/9/97/The_Earth_seen_from_Apollo_17.jpg"
)

for img in "${!IMAGES[@]}"; do
    url="${IMAGES[$img]}"
    echo "Downloading $img..."
    if ! curl -L --connect-timeout 10 --retry 3 -o "$ASSET_DIR/$img" "$url"; then
        echo "Download failed for $url, generating synthetic high-res image..."
        # Fallback: Create a 4000x3000 noise image using ImageMagick (~3-4MB JPG)
        convert -size 4000x3000 xc: +noise Random -quality 95 "$ASSET_DIR/$img"
    fi
done

# 2. Generate the Heavy ODP File using Python
# We use the system python which has odfpy installed (from env setup)
echo "Generating heavy presentation..."
cat << 'PY_SCRIPT' > /tmp/generate_odp.py
import sys
import os
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties
from odf.draw import Page, Frame, Image
from odf.text import P

def create_heavy_odp(output_path, asset_dir):
    doc = OpenDocumentPresentation()
    
    # Get images
    images = sorted([f for f in os.listdir(asset_dir) if f.endswith('.jpg')])
    
    for i, img_file in enumerate(images):
        # Create Page
        page = Page(name=f"Product_View_{i+1}")
        doc.presentation.addElement(page)
        
        # Add Title Text
        text_frame = Frame(width="25cm", height="2cm", x="1cm", y="1cm")
        text_frame.addElement(P(text=f"Showcase Image {i+1}: High Resolution Detail"))
        page.addElement(text_frame)
        
        # Add Image
        img_path = os.path.join(asset_dir, img_file)
        if os.path.exists(img_path):
            # Embed the image
            img_ref = doc.addPicture(img_path)
            
            # Create frame for image
            photo_frame = Frame(width="24cm", height="16cm", x="2cm", y="4cm")
            photo_frame.addElement(Image(href=img_ref))
            page.addElement(photo_frame)

    doc.save(output_path)
    print(f"Created presentation at {output_path}")

if __name__ == "__main__":
    create_heavy_odp(sys.argv[1], sys.argv[2])
PY_SCRIPT

# Run the generation script
python3 /tmp/generate_odp.py "$DATA_DIR/product_showcase_heavy.odp" "$ASSET_DIR"

# Clean up assets to save space
rm -rf "$ASSET_DIR"
chown ga:ga "$DATA_DIR/product_showcase_heavy.odp"

# Get initial file size for reference
INITIAL_SIZE=$(stat -c%s "$DATA_DIR/product_showcase_heavy.odp")
echo "$INITIAL_SIZE" > /tmp/initial_file_size.txt
echo "Initial file size: $((INITIAL_SIZE / 1024 / 1024)) MB"

# 3. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$DATA_DIR/product_showcase_heavy.odp' > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 60 || wait_for_window "product_showcase_heavy" 60

# Maximize and focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ensure maximized
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="