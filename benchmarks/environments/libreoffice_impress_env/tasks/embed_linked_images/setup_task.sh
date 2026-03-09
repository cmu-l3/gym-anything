#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Embed Linked Images Task ==="

# Define paths
USER_HOME="/home/ga"
DOCS_DIR="$USER_HOME/Documents/Presentations"
ASSETS_DIR="$USER_HOME/Desktop/assets"
ODP_FILE="$DOCS_DIR/quarterly_review.odp"

# Ensure directories exist
sudo -u ga mkdir -p "$DOCS_DIR"
sudo -u ga mkdir -p "$ASSETS_DIR"

# 1. Create dummy image assets
echo "Creating dummy chart images..."
if command -v convert >/dev/null; then
    # Use ImageMagick if available
    convert -size 800x600 xc:lightblue -pointsize 40 -fill black -gravity center -annotate +0+0 "Q3 Sales Chart\n(Linked File)" "$ASSETS_DIR/chart_sales.png"
    convert -size 800x600 xc:lightgreen -pointsize 40 -fill black -gravity center -annotate +0+0 "Growth Graph\n(Linked File)" "$ASSETS_DIR/graph_growth.png"
else
    # Fallback: Create simple text files masquerading as images? No, Impress needs real images.
    # The environment spec says imagemagick is installed.
    echo "Error: ImageMagick (convert) not found."
    exit 1
fi

sudo chown -R ga:ga "$ASSETS_DIR"

# 2. Create the ODP file with LINKED images
# We use Python to generate the ODP, then manually hack the XML to force external links
# (odfpy tends to embed by default, so we post-process the zip)

echo "Generating presentation file..."
cat << 'PYEOF' > /tmp/create_linked_odp.py
import os
import zipfile
import shutil
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, Image as DrawImage, TextBox
from odf.text import P

# Create basic structure
doc = OpenDocumentPresentation()

# Slide 1: Title
page1 = Page(name="Title")
doc.presentation.addElement(page1)
frame1 = Frame(width="20cm", height="3cm", x="2cm", y="10cm")
page1.addElement(frame1)
tb1 = TextBox()
frame1.addElement(tb1)
tb1.addElement(P(text="Quarterly Review Q3"))

# Slide 2: Sales (Image 1)
page2 = Page(name="Sales")
doc.presentation.addElement(page2)
# Add placeholder for image 1
# We use a dummy path here, we will replace it in XML later
img1 = DrawImage(href="Pictures/chart_sales.png", x="2cm", y="4cm", width="20cm", height="12cm")
page2.addElement(img1)

# Slide 3: Growth (Image 2)
page3 = Page(name="Growth")
doc.presentation.addElement(page3)
# Add placeholder for image 2
img2 = DrawImage(href="Pictures/graph_growth.png", x="2cm", y="4cm", width="20cm", height="12cm")
page3.addElement(img2)

# Save initially (this creates an ODP with missing internal pictures or empty refs)
output_path = "/tmp/temp_pres.odp"
doc.save(output_path)
print(f"Created base ODP at {output_path}")
PYEOF

python3 /tmp/create_linked_odp.py

# 3. Hack the ODP to force external links
echo "Modifying ODP to force external links..."
WORKING_DIR="/tmp/odp_hack"
rm -rf "$WORKING_DIR"
mkdir -p "$WORKING_DIR"
unzip -q /tmp/temp_pres.odp -d "$WORKING_DIR"

# Update content.xml to point to absolute file paths
# Note: In ODF, external links are usually file:///path/to/file
# Escaping slashes for sed
SALES_PATH="file://$ASSETS_DIR/chart_sales.png"
GROWTH_PATH="file://$ASSETS_DIR/graph_growth.png"

# Replace the hrefs
sed -i "s|Pictures/chart_sales.png|$SALES_PATH|g" "$WORKING_DIR/content.xml"
sed -i "s|Pictures/graph_growth.png|$GROWTH_PATH|g" "$WORKING_DIR/content.xml"

# Remove the Pictures directory if it exists (it shouldn't for external links)
rm -rf "$WORKING_DIR/Pictures"

# Re-zip
cd "$WORKING_DIR"
zip -qr "$ODP_FILE" .
cd -

sudo chown ga:ga "$ODP_FILE"

# 4. Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$ODP_FILE' > /tmp/impress_task.log 2>&1 &"

# Wait for process
wait_for_process "soffice" 15

# Wait for window
wait_for_window "LibreOffice Impress" 60

# Focus window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Select something to ensure focus isn't stuck
    su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
fi

# Record start time
date +%s > /tmp/task_start_time.txt
# Record initial file size
stat -c %s "$ODP_FILE" > /tmp/initial_file_size.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "📝 Instructions:"
echo "  1. The presentation has linked images on Slides 2 & 3."
echo "  2. Go to Edit > Links to External Files... (or similar)."
echo "  3. Break the links to embed the images."
echo "  4. Save the file."