#!/bin/bash
set -e
echo "=== Setting up Create Interactive Image Map Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
USER_NAME="ga"
USER_HOME="/home/ga"
PRES_DIR="$USER_HOME/Documents/Presentations"
FILE_NAME="system_dashboard.odp"
FILE_PATH="$PRES_DIR/$FILE_NAME"

# Ensure directories exist
sudo -u $USER_NAME mkdir -p "$PRES_DIR"

# 1. Generate the dashboard image asset using ImageMagick
# We create a 800x600 image with 3 distinct colored bands representing graphs
echo "Generating dashboard asset..."
IMAGE_PATH="/tmp/dashboard_monitor.png"

# Ensure ImageMagick is available
if ! command -v convert &> /dev/null; then
    echo "Installing ImageMagick..."
    apt-get update && apt-get install -y imagemagick
fi

convert -size 800x600 xc:white \
    -fill "#FFEBEE" -draw "rectangle 20,20 780,180" \
    -fill "#E8F5E9" -draw "rectangle 20,210 780,370" \
    -fill "#E3F2FD" -draw "rectangle 20,400 780,560" \
    -fill black -pointsize 24 \
    -draw "text 40,60 'CPU Usage - 45%'" \
    -draw "text 40,250 'Memory Usage - 2.4GB'" \
    -draw "text 40,440 'Network Traffic - 120Kbps'" \
    -stroke red -strokewidth 3 -fill none -draw "polyline 40,150 100,120 160,140 220,90 280,130 340,80" \
    -stroke green -strokewidth 3 -fill none -draw "polyline 40,340 100,330 160,335 220,320 280,325 340,310" \
    -stroke blue -strokewidth 3 -fill none -draw "polyline 40,530 100,500 160,540 220,480 280,520 340,490" \
    "$IMAGE_PATH"

chmod 644 "$IMAGE_PATH"

# 2. Create the ODP file structure programmatically
# We use python with odfpy to ensure a clean, valid file structure
echo "Creating starting presentation structure..."
cat << 'PYEOF' > /tmp/create_dashboard.py
import sys
import os
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties
from odf.draw import Page, Frame, Image, TextBox
from odf.text import P

def create_odp(output_path, image_path):
    doc = OpenDocumentPresentation()
    
    # Create layout style
    pl = PageLayout(name="MyLayout")
    doc.automaticstyles.addElement(pl)
    plp = PageLayoutProperties(margintop="0cm", marginbottom="0cm", marginleft="0cm", marginright="0cm", printorientation="landscape")
    pl.addElement(plp)
    master = MasterPage(name="Standard", pagelayoutname=pl)
    doc.masterstyles.addElement(master)

    # Slide 1: Dashboard (System Overview)
    page1 = Page(name="System Overview", masterpagename=master)
    doc.presentation.addElement(page1)
    
    # Title
    t1_frame = Frame(width="25cm", height="2cm", x="1cm", y="0.5cm")
    t1_box = TextBox()
    t1_frame.addElement(t1_box)
    t1_box.addElement(P(text="NOC System Dashboard (Click graphs for details)"))
    page1.addElement(t1_frame)
    
    # Image
    if os.path.exists(image_path):
        # Center the image roughly
        photo_frame = Frame(width="20cm", height="15cm", x="4cm", y="3cm")
        href = doc.addPicture(image_path)
        photo_image = Image(href=href)
        photo_frame.addElement(photo_image)
        page1.addElement(photo_frame)

    # Slide 2: CPU Details
    page2 = Page(name="Slide 2", masterpagename=master)
    doc.presentation.addElement(page2)
    t2_frame = Frame(width="25cm", height="3cm", x="1cm", y="1cm")
    t2_box = TextBox()
    t2_frame.addElement(t2_box)
    t2_box.addElement(P(text="CPU Details: Load Analysis"))
    page2.addElement(t2_frame)

    # Slide 3: Memory Details
    page3 = Page(name="Slide 3", masterpagename=master)
    doc.presentation.addElement(page3)
    t3_frame = Frame(width="25cm", height="3cm", x="1cm", y="1cm")
    t3_box = TextBox()
    t3_frame.addElement(t3_box)
    t3_box.addElement(P(text="Memory Details: Heap Allocation"))
    page3.addElement(t3_frame)

    # Slide 4: Network Details
    page4 = Page(name="Slide 4", masterpagename=master)
    doc.presentation.addElement(page4)
    t4_frame = Frame(width="25cm", height="3cm", x="1cm", y="1cm")
    t4_box = TextBox()
    t4_frame.addElement(t4_box)
    t4_box.addElement(P(text="Network Details: Interface Statistics"))
    page4.addElement(t4_frame)

    doc.save(output_path)
    print(f"Created {output_path}")

if __name__ == "__main__":
    create_odp(sys.argv[1], sys.argv[2])
PYEOF

python3 /tmp/create_dashboard.py "$FILE_PATH" "$IMAGE_PATH"
chown $USER_NAME:$USER_NAME "$FILE_PATH"

# Record initial file timestamp/size
stat -c %Y "$FILE_PATH" > /tmp/initial_file_mtime.txt
stat -c %s "$FILE_PATH" > /tmp/initial_file_size.txt

# 3. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - $USER_NAME -c "DISPLAY=:1 libreoffice --impress '$FILE_PATH' > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 30

# Maximize
DISPLAY=:1 wmctrl -r "LibreOffice Impress" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Ensure focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="