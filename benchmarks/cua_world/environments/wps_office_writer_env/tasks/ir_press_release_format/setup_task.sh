#!/bin/bash
set -euo pipefail

# Source utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up IR Press Release Format Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create directories
sudo -u ga mkdir -p /home/ga/Documents

# Generate the raw unstructured document using python-docx
python3 << 'PYEOF'
import os
from docx import Document

doc = Document()

# Plain, unformatted text that needs formatting
doc.add_paragraph("Meridian Corp Announces Fourth Quarter and Full Year Results")

doc.add_paragraph(
    "Meridian Corp today reported financial results for the fourth quarter and full year "
    "ended December 31, 2024, demonstrating strong execution across all business segments."
)

doc.add_paragraph(
    "For the fourth quarter, Revenue was $89.6 billion and for FY 2024 it was $350.2 billion. "
    "Operating Income for Q4 2024 reached $14.2 billion, while FY 2024 Operating Income was $52.4 billion. "
    "Net Income stood at $11.5 billion in Q4 2024 and $43.8 billion for the full year. "
    "Diluted EPS was $2.15 in the fourth quarter and $8.20 for FY 2024."
)

doc.add_paragraph("About Meridian Corp")

doc.add_paragraph(
    "Meridian Corp is a leading global provider of enterprise technology solutions, serving "
    "customers in over 150 countries. We are committed to driving innovation and delivering "
    "sustainable value to our shareholders."
)

doc.add_paragraph("Safe Harbor / Forward-Looking Statements")

doc.add_paragraph(
    "This press release contains forward-looking statements within the meaning of the Private "
    "Securities Litigation Reform Act of 1995. These forward-looking statements include, but are "
    "not limited to, statements regarding our financial outlook, future growth, and business strategy. "
    "Actual results may differ materially from those projected due to various risks and uncertainties. "
    "We undertake no obligation to update any forward-looking statements."
)

doc.save("/home/ga/Documents/Earnings_Release_Raw.docx")
PYEOF

# Ensure proper permissions
sudo chown ga:ga /home/ga/Documents/Earnings_Release_Raw.docx
sudo chmod 644 /home/ga/Documents/Earnings_Release_Raw.docx

# Start WPS Writer and open the raw document
echo "Starting WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/Earnings_Release_Raw.docx &"
sleep 5

# Wait for window and maximize it
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    echo "Found WPS window: $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    dismiss_wps_dialogs
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="