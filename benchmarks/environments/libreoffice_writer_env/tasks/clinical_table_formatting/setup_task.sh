#!/bin/bash
set -euo pipefail

echo "=== Setting up Clinical Table Formatting Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the raw clinical data table using python-docx
# We create a flat table that needs formatting
python3 << 'PYEOF'
import random
from docx import Document
from docx.shared import Pt

def create_raw_table():
    doc = Document()
    
    # Add context text
    doc.add_paragraph("Table 1: Demographics and Baseline Characteristics")
    
    # Create table: 6 columns, 7 rows (1 header + 6 data)
    table = doc.add_table(rows=1, cols=6)
    table.style = 'Table Grid' # Standard grid to start with
    
    # Header row (Flat, unmerged)
    hdr_cells = table.rows[0].cells
    headers = ["Characteristic", "Placebo Mean", "Placebo SD", "Sarilumab Mean", "Sarilumab SD", "P-value"]
    for i, text in enumerate(headers):
        hdr_cells[i].text = text
    
    # Data rows
    data = [
        ("Age (years)", "58.4", "10.2", "59.1", "9.8", "0.65"),
        ("BMI (kg/m²)", "28.1", "5.4", "27.9", "4.9", "0.72"),
        ("Duration of RA (yrs)", "8.5", "6.2", "9.1", "7.1", "0.48"),
        ("CRP (mg/L)", "12.4", "15.1", "13.2", "16.8", "0.55"),
        ("DAS28-CRP", "5.1", "0.9", "5.2", "1.1", "0.34"),
        ("HAQ-DI Score", "1.6", "0.6", "1.5", "0.7", "0.29")
    ]
    
    for row_data in data:
        row_cells = table.add_row().cells
        for i, text in enumerate(row_data):
            row_cells[i].text = text
            
    doc.save("/home/ga/Documents/draft_demographics.docx")
    print("Created raw clinical table document.")

if __name__ == "__main__":
    create_raw_table()
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/draft_demographics.docx
chmod 666 /home/ga/Documents/draft_demographics.docx

# Ensure LibreOffice is not running
pkill -f soffice.bin || true
sleep 1

# Launch LibreOffice Writer with the file
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/draft_demographics.docx > /tmp/writer.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "draft_demographics" 30

# Maximize and focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (Tip of the Day, etc.)
sleep 2
safe_xdotool ga :1 key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="