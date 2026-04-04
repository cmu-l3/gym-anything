#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Expense Table Formulas Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Create the source document using python-docx
# We use Python to generate a clean DOCX with a table and data
python3 << 'PYEOF'
import os
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title
heading = doc.add_heading('Q1 Department Expense Report', level=1)
heading.alignment = WD_ALIGN_PARAGRAPH.CENTER

subtitle = doc.add_paragraph('Administrative Services Division — Fiscal Year 2024')
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph('')

# Intro text
doc.add_paragraph(
    'This report summarizes departmental operating expenses for the first quarter '
    '(January–March 2024). All figures are in US dollars. Please populate the '
    'missing totals using table formulas.'
)
doc.add_paragraph('')

# Table Data
# Headers: Category, Jan, Feb, Mar, Q1 Total
# Row 1: Office Supplies, 1245, 987, 1102
# Row 2: Travel & Lodging, 3450, 2890, 4210
# Row 3: Software Licenses, 5600, 5600, 5600
# Row 4: Training & Dev, 2100, 0, 3500
# Row 5: Equipment, 8750, 1200, 0
# Row 6: Miscellaneous, 345, 567, 289
# Row 7: Monthly Total, (empty), (empty), (empty), (empty)

headers = ['Category', 'January', 'February', 'March', 'Q1 Total']
data = [
    ['Office Supplies', '1245', '987', '1102', ''],
    ['Travel & Lodging', '3450', '2890', '4210', ''],
    ['Software Licenses', '5600', '5600', '5600', ''],
    ['Training & Development', '2100', '0', '3500', ''],
    ['Equipment & Furniture', '8750', '1200', '0', ''],
    ['Miscellaneous', '345', '567', '289', ''],
    ['Monthly Total', '', '', '', '']  # Totals row
]

table = doc.add_table(rows=len(data)+1, cols=len(headers))
table.style = 'Table Grid'

# Set headers
hdr_cells = table.rows[0].cells
for i, text in enumerate(headers):
    run = hdr_cells[i].paragraphs[0].add_run(text)
    run.bold = True
    hdr_cells[i].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER

# Fill data
for i, row_data in enumerate(data):
    row_cells = table.rows[i+1].cells
    for j, cell_data in enumerate(row_data):
        row_cells[j].text = cell_data
        # Right align numbers
        if j > 0:
            row_cells[j].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT

# Save
output_path = "/home/ga/Documents/expense_report_q1.docx"
doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Set ownership
chown ga:ga /home/ga/Documents/expense_report_q1.docx
chmod 666 /home/ga/Documents/expense_report_q1.docx

# Launch LibreOffice Writer with the document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/expense_report_q1.docx > /tmp/writer_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
if wait_for_window "LibreOffice Writer" 60; then
    echo "Writer window detected."
else
    # Fallback check for document name in title
    wait_for_window "expense_report" 30 || true
fi

# Maximize window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    echo " maximizing window $wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="