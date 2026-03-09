#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Price List Conversion Task ==="

# Create documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Record task start time
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# Create the raw inventory dump file with tab-separated values
# We use python-docx to create a .docx file containing raw text (not a table yet)
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Add instructions or context (optional, but realistic to have just the data)
# We will just add the raw data lines.

# Data: Product Name, Category, SKU, Price
# Note: Prices are intentionally unsorted
data = [
    "Product Name\tCategory\tSKU\tPrice",
    "Executive Leather Desk Chair\tOffice\tOFF-001\t$349.99",
    "Minimalist Oak Dining Table\tDining\tDIN-042\t$899.50",
    "Velvet Sectional Sofa\tLiving Room\tLIV-203\t$1,250.00",
    "Industrial Bookshelf\tOffice\tOFF-105\t$189.00",
    "Queen Size Memory Foam Mattress\tBedroom\tBED-331\t$550.00",
    "Bedside Lamp (Set of 2)\tBedroom\tLIG-009\t$85.00",
    "Ergonomic Standing Desk\tOffice\tOFF-202\t$425.00",
    "Outdoor Patio Set\tOutdoor\tOUT-555\t$699.99",
    "Ceramic Vase\tDecor\tDEC-012\t$24.50",
    "Handwoven Area Rug (8x10)\tLiving Room\tRUG-099\t$320.00",
    "Marble Coffee Table\tLiving Room\tLIV-110\t$450.00",
    "Dining Chair (Set of 4)\tDining\tDIN-004\t$260.00",
    "Smart LED Bulb\tLighting\tLIG-101\t$15.99",
    "Floating Wall Shelf\tDecor\tDEC-055\t$35.00",
    "Leather Recliner\tLiving Room\tLIV-888\t$799.00"
]

# Add as plain paragraphs
for line in data:
    p = doc.add_paragraph(line)
    p.style = doc.styles['Normal']
    # Ensure no weird formatting pre-exists
    p.paragraph_format.space_after = Pt(0)

doc.save("/home/ga/Documents/raw_inventory_dump.docx")
print("Created raw inventory dump file.")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/raw_inventory_dump.docx
chmod 666 /home/ga/Documents/raw_inventory_dump.docx

# Open the file in LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/raw_inventory_dump.docx > /tmp/writer.log 2>&1 &"

# Wait for Writer to open
wait_for_window "raw_inventory_dump" 60

# Maximize the window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss any initial dialogs (like "What's New")
    sleep 2
    safe_xdotool ga :1 key Escape
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="