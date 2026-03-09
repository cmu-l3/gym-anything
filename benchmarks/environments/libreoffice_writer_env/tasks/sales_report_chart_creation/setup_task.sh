#!/bin/bash
set -e
echo "=== Setting up Sales Report Chart Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 1. Create the initial document with the data table
# We use python-docx to create a DOCX first, then convert to ODT.
# This ensures we have a clean, valid file structure.
echo "Generating source document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Add Title
heading = doc.add_heading('2024 Annual Performance Review', 0)
heading.alignment = 1  # Center

doc.add_paragraph(
    "The following report summarizes the financial performance across all operating regions "
    "for the fiscal year 2024. Please review the quarterly breakdown below."
)

# Add Table
# Data: Region, Q1, Q2, Q3, Q4
data = [
    ['Region', 'Q1', 'Q2', 'Q3', 'Q4'],
    ['North', '12.5', '14.2', '13.8', '18.5'],
    ['South', '10.1', '11.5', '10.8', '14.2'],
    ['East',  '22.4', '24.1', '23.5', '28.9'],
    ['West',  '18.2', '19.5', '19.1', '21.0']
]

table = doc.add_table(rows=len(data), cols=len(data[0]))
table.style = 'Table Grid'

for r, row_data in enumerate(data):
    row = table.rows[r]
    for c, cell_data in enumerate(row_data):
        row.cells[c].text = str(cell_data)

doc.add_paragraph("")
doc.add_paragraph("Summary: The East region continues to lead in total revenue, though North showed significant growth in Q4.")

doc.save("/home/ga/Documents/temp_source.docx")
PYEOF

# 2. Convert to ODT (so the agent works in native ODF format as requested)
echo "Converting to ODT..."
libreoffice --headless --convert-to odt --outdir /home/ga/Documents /home/ga/Documents/temp_source.docx > /dev/null 2>&1
mv /home/ga/Documents/temp_source.odt /home/ga/Documents/sales_report.odt
rm /home/ga/Documents/temp_source.docx
chown ga:ga /home/ga/Documents/sales_report.odt

# 3. Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/sales_report.odt > /tmp/writer.log 2>&1 &"

# 4. Wait for window and setup UI
wait_for_window "sales_report" 60
sleep 2

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss any first-run dialogs (Safe Mode, Tips, etc.)
    sleep 2
    safe_xdotool ga :1 key Escape
    sleep 0.5
    safe_xdotool ga :1 key Escape
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="