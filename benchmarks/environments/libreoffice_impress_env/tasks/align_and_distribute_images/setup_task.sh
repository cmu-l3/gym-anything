#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Align and Distribute Images Task ==="

# Define paths
PRESENTATIONS_DIR="/home/ga/Documents/Presentations"
mkdir -p "$PRESENTATIONS_DIR"
TARGET_FILE="$PRESENTATIONS_DIR/product_showcase.odp"
ASSETS_DIR="/tmp/assets"
mkdir -p "$ASSETS_DIR"

# Download dummy product images (using reliable placeholder services or simple shapes generation)
# To ensure robustness without external deps, we'll generate images using ImageMagick
echo "Generating product images..."
convert -size 400x400 xc:lightblue -gravity center -pointsize 40 -annotate 0 "WATCH" "$ASSETS_DIR/watch.jpg"
convert -size 400x350 xc:lightgreen -gravity center -pointsize 40 -annotate 0 "CAMERA" "$ASSETS_DIR/camera.jpg"
convert -size 400x400 xc:lightpink -gravity center -pointsize 40 -annotate 0 "HEADPHONES" "$ASSETS_DIR/headphones.jpg"

# Generate the ODP file with "messy" layout using python-odfpy
echo "Creating messy presentation file..."
python3 << PYEOF
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, Image
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties

doc = OpenDocumentPresentation()

# Slide 1: Title
page1 = Page(name="Slide1")
doc.presentation.addElement(page1)
frame_title = Frame(width="25cm", height="3cm", x="1.5cm", y="2cm")
page1.addElement(frame_title)
frame_title.addElement(P(text="New Product Lineup 2024"))

# Slide 2: Messy Images
page2 = Page(name="New Arrivals")
doc.presentation.addElement(page2)

# Title for Slide 2
frame_s2_title = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
page2.addElement(frame_s2_title)
frame_s2_title.addElement(P(text="New Arrivals - Need Alignment"))

# Define messy coordinates (cm)
# Image 1 (Watch): Low Y, Left X
# Image 2 (Camera): High Y, Middle X
# Image 3 (Headphones): Low Y, Right X, uneven spacing
# We want them to NOT be centered vertically (different Ys) and NOT distributed evenly (uneven gaps)

images = [
    {"path": "$ASSETS_DIR/watch.jpg", "x": "2cm", "y": "5cm", "w": "5cm", "h": "5cm"},
    {"path": "$ASSETS_DIR/camera.jpg", "x": "9cm", "y": "8cm", "w": "5cm", "h": "4.5cm"},
    {"path": "$ASSETS_DIR/headphones.jpg", "x": "19cm", "y": "4cm", "w": "5cm", "h": "5cm"}
]

for img_data in images:
    # Create image frame
    photo_frame = Frame(
        width=img_data["w"], 
        height=img_data["h"], 
        x=img_data["x"], 
        y=img_data["y"]
    )
    # Add image reference
    image_ref = Image(href=img_data["path"])
    photo_frame.addElement(image_ref)
    page2.addElement(photo_frame)

doc.save("$TARGET_FILE")
print(f"Created $TARGET_FILE with 3 misaligned images")
PYEOF

# Ensure permissions
chown -R ga:ga "$PRESENTATIONS_DIR"

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$TARGET_FILE' > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

# Focus and Maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key F11  # Fullscreen/Maximize
    sleep 1
fi

# Navigate to Slide 2 so agent sees the problem immediately
echo "Navigating to Slide 2..."
safe_xdotool ga :1 key Page_Down

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Setup complete."