#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prepare Report Task ==="

# Define paths
DOCS_DIR="/home/ga/Documents/Presentations"
ODP_PATH="$DOCS_DIR/monthly_review.odp"
ODS_PATH="$DOCS_DIR/financial_data.ods"

# Ensure directory exists and is empty of old task files
rm -rf "$DOCS_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

# Generate the files using python3 and odfpy
# We need to generate the ODS first, then the ODP linking to it
echo "Generating content..."

python3 << PYEOF
import os
from odf.opendocument import OpenDocumentSpreadsheet, OpenDocumentPresentation
from odf.table import Table, TableRow, TableCell
from odf.text import P, Span
from odf.draw import Page, Frame, TextBox, Object, ObjectOle
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, ParagraphProperties

# 1. Create the Spreadsheet (financial_data.ods)
ods = OpenDocumentSpreadsheet()
table = Table(name="Financials")
ods.spreadsheet.addElement(table)

data = [
    ["Category", "Q1", "Q2", "Q3", "Q4"],
    ["Revenue", "12000", "15000", "13500", "18000"],
    ["COGS", "8000", "9500", "8500", "11000"],
    ["Net Income", "4000", "5500", "5000", "7000"]
]

for row_data in data:
    tr = TableRow()
    table.addElement(tr)
    for val in row_data:
        tc = TableCell()
        tc.addElement(P(text=val))
        tr.addElement(tc)

ods.save("$ODS_PATH")
print(f"Created $ODS_PATH")

# 2. Create the Presentation (monthly_review.odp)
odp = OpenDocumentPresentation()

# --- Setup Master Page with Confidential Watermark ---
# We need to define styles for the master page
master_page_name = "ConfidentialMaster"

# Create a master page
master = MasterPage(name=master_page_name, pagelayoutname="PM1")
odp.masterstyles.addElement(master)

# Add the standard presentation objects to master (optional but good for realism)
# Add the Confidential Watermark to the master
watermark_frame = Frame(width="15cm", height="1.5cm", x="6cm", y="18cm") # Bottom center
watermark_textbox = TextBox()
watermark_frame.addElement(watermark_textbox)
# Style for red bold text
red_style = Style(name="RedBold", family="text")
red_style.addElement(TextProperties(color="#ff0000", fontweight="bold", fontsize="14pt"))
odp.styles.addElement(red_style)

watermark_p = P(stylename=red_style, text="Confidential - Internal Use Only")
watermark_textbox.addElement(watermark_p)
master.addElement(watermark_frame)

# --- Slide 1: Title ---
page1 = Page(name="Title Slide", masterpagename=master_page_name)
odp.presentation.addElement(page1)

title_frame = Frame(width="20cm", height="3cm", x="4cm", y="4cm")
title_textbox = TextBox()
title_frame.addElement(title_textbox)
title_textbox.addElement(P(text="Monthly Business Review"))
title_textbox.addElement(P(text="Prepared for External Client"))
page1.addElement(title_frame)

# --- Slide 2: Data Link ---
page2 = Page(name="Financial Data", masterpagename=master_page_name)
odp.presentation.addElement(page2)

# Title for Slide 2
s2_title = Frame(width="20cm", height="2cm", x="2cm", y="1cm")
s2_tb = TextBox()
s2_title.addElement(s2_tb)
s2_tb.addElement(P(text="Q1-Q4 Financial Performance"))
page2.addElement(s2_title)

# OLE Object linking to the spreadsheet
# Note: Creating a working OLE link programmatically in ODF is complex.
# We will create a draw:object with xlink:href pointing to the file.
# LibreOffice interprets this as a linked object.
ole_frame = Frame(width="20cm", height="10cm", x="4cm", y="5cm")
# xlink:href relative path to file
ole_object = Object(href="./financial_data.ods") 
ole_frame.addElement(ole_object)
page2.addElement(ole_frame)

odp.save("$ODP_PATH")
print(f"Created $ODP_PATH")
PYEOF

# Fix permissions
sudo chown -R ga:ga "$DOCS_DIR"

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$ODP_PATH' > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 60

# Focus window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    safe_xdotool ga :1 key F11
    sleep 0.5
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="