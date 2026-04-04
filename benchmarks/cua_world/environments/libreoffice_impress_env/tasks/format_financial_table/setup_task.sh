#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Format Financial Table Task ==="

# Create directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Generate the ODP file with an unformatted table using python and odfpy
# We use the python environment available in the container
python3 << 'PYEOF'
import os
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.table import Table, TableRow, TableCell, TableColumn
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, TableColumnProperties

doc = OpenDocumentPresentation()

# Slide 1: Title
page1 = Page(name="Title Slide")
doc.presentation.addElement(page1)
frame1 = Frame(width="15cm", height="5cm", x="2cm", y="5cm")
textbox1 = TextBox()
textbox1.addElement(P(text="Q4 Financial Results"))
frame1.addElement(textbox1)
page1.addElement(frame1)

# Slide 2: The Table
page2 = Page(name="Financials")
doc.presentation.addElement(page2)

# Title for Slide 2
title_frame = Frame(width="20cm", height="2cm", x="2cm", y="1cm")
title_box = TextBox()
title_box.addElement(P(text="Quarterly Breakdown"))
title_frame.addElement(title_box)
page2.addElement(title_frame)

# Create Table Frame
table_frame = Frame(width="22cm", height="10cm", x="2cm", y="4cm")
table = Table(name="FinancialTable")

# Define columns (4 columns)
for _ in range(4):
    table.addElement(TableColumn())

# Data for rows
# Row 1: Headers (Unmerged initially)
# A1: FY 2023, B1: (empty), C1: FY 2024, D1: (empty)
row1 = TableRow()
for text in ["FY 2023", "", "FY 2024", ""]:
    cell = TableCell()
    cell.addElement(P(text=text))
    row1.addElement(cell)
table.addElement(row1)

# Row 2: Subheaders
row2 = TableRow()
for text in ["Q3", "Q4", "Q3", "Q4"]:
    cell = TableCell()
    cell.addElement(P(text=text))
    row2.addElement(cell)
table.addElement(row2)

# Row 3: Data 1
row3 = TableRow()
for text in ["$1.2M", "$1.4M", "$1.3M", "$1.5M"]:
    cell = TableCell()
    cell.addElement(P(text=text))
    row3.addElement(cell)
table.addElement(row3)

# Row 4: Data 2
row4 = TableRow()
for text in ["$0.8M", "$0.9M", "$0.8M", "$1.0M"]:
    cell = TableCell()
    cell.addElement(P(text=text))
    row4.addElement(cell)
table.addElement(row4)

# Row 5: Total (Plain text initially)
row5 = TableRow()
cell_total = TableCell()
cell_total.addElement(P(text="Total"))
row5.addElement(cell_total)
for text in ["$2.0M", "$2.3M", "$2.1M", "$2.5M"]: # Offset since Total takes first col? No, just filling cells.
    # Actually let's just fill 4 cells. "Total" in first, rest numbers.
    pass

# Re-doing Row 5 correctly
row5_final = TableRow()
row5_final.addElement(TableCell()) # Empty A5 or "Total"? Let's put Total in A5
row5_final.childNodes[0].addElement(P(text="Total Revenue"))

for text in ["$2.0M", "$2.3M", "$2.5M"]: # B5, C5, D5
    cell = TableCell()
    cell.addElement(P(text=text))
    row5_final.addElement(cell)
table.addElement(row5_final)

table_frame.addElement(table)
page2.addElement(table_frame)

output_path = "/home/ga/Documents/Presentations/Q4_Financials.odp"
doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Fix permissions
sudo chown ga:ga /home/ga/Documents/Presentations/Q4_Financials.odp

# Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/Q4_Financials.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
wait_for_window "LibreOffice Impress" 60

# Focus window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    safe_xdotool ga :1 key F11
    sleep 1
    # Ensure Slide 2 is selected (Down arrow once)
    safe_xdotool ga :1 key Page_Down
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="