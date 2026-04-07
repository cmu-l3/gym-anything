#!/bin/bash
set -euo pipefail

echo "=== Setting up Investor Relations Deck Assembly Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Clean up any existing instances of ONLYOFFICE
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
sleep 1

# Create the necessary directories
sudo -u ga mkdir -p "/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "/home/ga/Documents/Presentations"

# Create the source files using a Python script inside the container
cat > /tmp/generate_data.py << 'PYEOF'
#!/usr/bin/env python3
import os
from docx import Document
from openpyxl import Workbook
from pptx import Presentation

# 1. Generate Shareholder Letter (DOCX)
doc = Document()
doc.add_heading('Airbnb Q3 2023 Shareholder Letter', 0)
doc.add_paragraph("Q3 2023 was a strong quarter for Airbnb. We saw continued growth in our core business and demonstrated the strength of our business model.")

doc.add_heading('Business Highlights', 1)
doc.add_paragraph("Nights and Experiences Booked reached 113.2 million, showing strong demand across all regions. This represents a substantial year-over-year increase.")
doc.add_paragraph("Gross Booking Value (GBV) was $18.3 billion, a significant increase year-over-year, driven by resilient travel demand and stable average daily rates.")

doc.add_heading('Strategic Priorities', 1)
doc.add_paragraph("Looking ahead, we are focused on three strategic priorities:")
doc.add_paragraph("1. Make hosting mainstream: We are introducing new tools to make it easier than ever to host.")
doc.add_paragraph("2. Perfect the core service: We are listening to our community and improving our product.")
doc.add_paragraph("3. Expand beyond the core: We have launched new initiatives to expand our addressable market.")
doc.save('/home/ga/Documents/TextDocuments/Airbnb_Q3_2023_Shareholder_Letter.docx')

# 2. Generate Financials (XLSX)
wb = Workbook()
ws = wb.active
ws.title = "Q3 2023 Financials"
ws.append(["Airbnb, Inc."])
ws.append(["Condensed Consolidated Statements of Operations (in millions)"])
ws.append([])
ws.append(["", "Q3 2023"])
ws.append(["Total Revenue", 3397])
ws.append(["Costs and expenses", 1438])
ws.append(["Operating income", 1959])
ws.append(["Provision for income taxes", -2415]) # One time tax benefit
ws.append(["Net Income", 4374])
wb.save('/home/ga/Documents/Spreadsheets/Airbnb_Q3_2023_Financials.xlsx')

# 3. Generate Presentation Template (PPTX)
prs = Presentation()
slide_layout = prs.slide_layouts[0]
slide = prs.slides.add_slide(slide_layout)
title = slide.shapes.title
title.text = "Q3 Earnings Template"
subtitle = slide.placeholders[1]
subtitle.text = "Draft Presentation"
prs.save('/home/ga/Documents/Presentations/Q3_Earnings_Template.pptx')

# Fix permissions
os.system("chown -R ga:ga /home/ga/Documents/")
PYEOF

echo "Generating realistic business documents..."
sudo -u ga python3 /tmp/generate_data.py

# Launch ONLYOFFICE with the three files open
echo "Launching ONLYOFFICE..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors \
    /home/ga/Documents/Presentations/Q3_Earnings_Template.pptx \
    /home/ga/Documents/TextDocuments/Airbnb_Q3_2023_Shareholder_Letter.docx \
    /home/ga/Documents/Spreadsheets/Airbnb_Q3_2023_Financials.xlsx > /tmp/onlyoffice.log 2>&1 &

# Wait for ONLYOFFICE window to appear
echo "Waiting for application window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Desktop Editors\|ONLYOFFICE"; then
        echo "ONLYOFFICE window detected."
        break
    fi
    sleep 1
done

# Allow UI to settle
sleep 5

# Maximize and focus ONLYOFFICE
WID=$(DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE\|Desktop Editors" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Dismiss any welcome dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="