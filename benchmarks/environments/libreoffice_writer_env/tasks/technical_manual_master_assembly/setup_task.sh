#!/bin/bash
set -e
echo "=== Setting up Master Document Assembly Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
DOCS_DIR="/home/ga/Documents/Hydra_Manual"
mkdir -p "$DOCS_DIR"

# Generate Source content using python-docx then convert to ODT
# (Leveraging the environment's python-docx library to create structured content easily)
cat << 'EOF' > /tmp/gen_docs.py
import os
from docx import Document

def create_doc(filename, title, body_text):
    doc = Document()
    doc.add_heading(title, level=1)
    doc.add_paragraph(body_text)
    
    # Add subsections to make the TOC meaningful
    doc.add_heading('Overview', level=2)
    doc.add_paragraph(f"General overview of {title.lower()}.")
    
    doc.add_heading('Specific Instructions', level=2)
    doc.add_paragraph(f"Detailed instructions for {title.lower()} follow standard protocols.")
    
    doc.save(filename)

base_dir = "/home/ga/Documents/Hydra_Manual"

# 01 Safety
create_doc(
    os.path.join(base_dir, "01_safety.docx"),
    "Safety Precautions",
    "WARNING: High pressure hydraulic fluid can cause severe injury. Always depressurize the system before maintenance."
)

# 02 Operation
create_doc(
    os.path.join(base_dir, "02_operation.docx"),
    "System Operation",
    "1. Ensure all valves are closed.\n2. Engage the primary pump.\n3. Monitor pressure gauges until 2000 PSI is reached."
)

# 03 Maintenance
create_doc(
    os.path.join(base_dir, "03_maintenance.docx"),
    "Maintenance Schedule",
    "Daily: Check fluid levels.\nWeekly: Inspect hoses for wear.\nMonthly: Replace return line filters (Part #H-992)."
)
EOF

# Run generator
echo "Generating source documents..."
python3 /tmp/gen_docs.py

# Convert DOCX to ODT using headless Writer
# Master Documents work best with native ODT files
echo "Converting source files to ODT format..."
cd "$DOCS_DIR"
# Convert individually to ensure success
for f in *.docx; do
    libreoffice --headless --convert-to odt "$f" > /dev/null 2>&1
done

# Clean up DOCX artifacts and script
rm *.docx
rm /tmp/gen_docs.py

# Ensure permissions are correct
chown -R ga:ga "$DOCS_DIR"

# Launch LibreOffice Writer (Empty)
echo "Starting LibreOffice Writer..."
if ! pgrep -f "libreoffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer --norestore &"
fi

# Wait for window
wait_for_window "LibreOffice Writer" 60

# Maximize and Focus
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (Tip of the Day, etc.)
sleep 5
safe_xdotool ga :1 key Escape
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="