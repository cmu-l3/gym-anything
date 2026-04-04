#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Restore Missing Assets Task ==="

# 1. Define Paths
BASE_DIR="/home/ga/Documents"
PRES_DIR="$BASE_DIR/Presentations"
ASSETS_DIR="$BASE_DIR/Assets"
OLD_DIR="$ASSETS_DIR/Old"
NEW_DIR="$ASSETS_DIR/New"
PRES_FILE="$PRES_DIR/Q3_Performance.odp"
IMAGE_NAME="revenue_chart.png"

# 2. Clean up and create directories
sudo rm -rf "$PRES_DIR" "$ASSETS_DIR"
sudo -u ga mkdir -p "$PRES_DIR"
sudo -u ga mkdir -p "$OLD_DIR"
sudo -u ga mkdir -p "$NEW_DIR"

# 3. Generate the Chart Image (in OLD location first so ODP creation works)
echo "Generating chart asset..."
python3 << PYEOF
import matplotlib.pyplot as plt
import numpy as np

# Create a realistic looking revenue chart
plt.figure(figsize=(10, 6), dpi=100)
months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep']
revenue = [1.2, 1.5, 1.8, 1.4, 2.1, 2.5, 2.8, 2.4, 3.2]

plt.bar(months, revenue, color='#4c72b0')
plt.title('Q3 Revenue Performance (in Millions)', fontsize=16)
plt.xlabel('Month')
plt.ylabel('Revenue ($M)')
plt.grid(axis='y', linestyle='--', alpha=0.7)
plt.tight_layout()

# Save to the OLD location initially so we can link it
plt.savefig("$OLD_DIR/$IMAGE_NAME")
print(f"Created chart at $OLD_DIR/$IMAGE_NAME")
PYEOF

# Ensure ownership
sudo chown -R ga:ga "$BASE_DIR"

# 4. Create the ODP file referencing the image in OLD_DIR
echo "Creating presentation with linked image..."
python3 << PYEOF
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, Image, TextBox
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties
import os

doc = OpenDocumentPresentation()

# Slide 1: Title
page1 = Page(name="Title Slide")
doc.presentation.addElement(page1)
frame1 = Frame(width="25cm", height="3cm", x="1.5cm", y="8cm")
textbox1 = TextBox()
textbox1.addElement(P(text="Q3 Financial Performance Review"))
frame1.addElement(textbox1)
page1.addElement(frame1)

# Slide 2: The Broken Link Slide
page2 = Page(name="Revenue Chart")
doc.presentation.addElement(page2)

# Title
frame_title = Frame(width="25cm", height="2cm", x="1.5cm", y="1cm")
tb_title = TextBox()
tb_title.addElement(P(text="Monthly Revenue Analysis"))
frame_title.addElement(tb_title)
page2.addElement(frame_title)

# The Linked Image
# Note: We point to the file in OLD_DIR relative to PRES_DIR
# ../Assets/Old/revenue_chart.png
rel_path = "../Assets/Old/$IMAGE_NAME"

# Create image frame
image_frame = Frame(width="20cm", height="12cm", x="4cm", y="4cm")
# href needs to be the relative URI
image = Image(href=rel_path)
image_frame.addElement(image)
page2.addElement(image_frame)

doc.save("$PRES_FILE")
print("Presentation created successfully.")
PYEOF

# 5. BREAK THE LINK
# Move the image from OLD to NEW, leaving the ODP pointing to an empty folder
echo "Breaking the link by moving asset..."
sudo -u ga mv "$OLD_DIR/$IMAGE_NAME" "$NEW_DIR/$IMAGE_NAME"
# Optional: verify old file is gone
if [ -f "$OLD_DIR/$IMAGE_NAME" ]; then
    echo "Error: Failed to move file"
    exit 1
fi

# 6. Record Initial State
echo "$(date +%s)" > /tmp/task_start_time
stat -c %Y "$PRES_FILE" > /tmp/initial_file_mtime

# 7. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$PRES_FILE' > /tmp/impress.log 2>&1 &"

# 8. Wait for load and setup window
wait_for_window "LibreOffice Impress" 60 || echo "Warning: Window wait timeout"

# Focus window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Wait a moment for the "Update Links" dialog which might appear
    sleep 2
    # If a dialog asks to update links, we want the agent to handle it or dismiss it. 
    # Usually, if links are broken, it might prompt. 
    # For this task, we assume the agent sees the broken icon.
    # We'll dismiss any initial popups just in case to let agent interact with main UI
    safe_xdotool ga :1 key Escape 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task ready: Presentation open with broken link on Slide 2."