#!/bin/bash
set -euo pipefail

echo "=== Setting up Proxy Statement Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
sudo -u ga mkdir -p /home/ga/Documents

# Generate the raw proxy statement document
echo "Generating raw proxy statement document..."
sudo -u ga python3 << 'PYEOF'
from docx import Document

doc = Document()

# Main Title (Raw, unformatted)
doc.add_paragraph("Compensation Discussion and Analysis")

# Body Text
doc.add_paragraph(
    "This Compensation Discussion and Analysis (CD&A) describes our executive compensation "
    "program for our Named Executive Officers (NEOs) for the fiscal year ended December 31, 2023."
)

# Subsection 1
doc.add_paragraph("Executive Summary")
doc.add_paragraph(
    "Fiscal 2023 was a year of strong financial and operational performance. We exceeded our "
    "revenue and profitability targets, delivering significant value to our shareholders."
)

# Subsection 2
doc.add_paragraph("Compensation Philosophy")
doc.add_paragraph(
    "Our executive compensation program is designed to attract, retain, and motivate highly "
    "qualified executives. We emphasize 'pay-for-performance' by linking a significant portion "
    "of compensation to the achievement of corporate and individual goals."
)

# Subsection 3
doc.add_paragraph("Elements of Compensation")
doc.add_paragraph(
    "The primary elements of our executive compensation program are base salary, annual cash "
    "incentive bonuses, and long-term equity incentives."
)

# Subsection 4
doc.add_paragraph("Summary Compensation Table")
doc.add_paragraph(
    "The following table summarizes the total compensation earned by our NEOs for the fiscal year "
    "ended December 31, 2023."
)

# Pipe-delimited text to be converted to a table
doc.add_paragraph("Name and Principal Position|Year|Salary|Bonus|Stock Awards|Total")
doc.add_paragraph("Jane Doe, Chief Executive Officer|2023|$1,200,000 [1]|$2,500,000|$10,000,000|$13,700,000")
doc.add_paragraph("John Smith, Chief Financial Officer|2023|$600,000|$800,000|$3,000,000 [2]|$4,400,000")
doc.add_paragraph("Alice Jones, Chief Operating Officer|2023|$650,000|$850,000|$3,200,000|$4,700,000")

doc.add_paragraph("")
doc.add_paragraph("Footnotes:")
doc.add_paragraph("[1] Includes retroactive base salary adjustment approved by the Compensation Committee in March 2023.")
doc.add_paragraph("[2] Represents the aggregate grant date fair value of Restricted Stock Units (RSUs) computed in accordance with FASB ASC Topic 718.")

doc.save("/home/ga/Documents/proxy_statement_raw.docx")
PYEOF

echo "File created at /home/ga/Documents/proxy_statement_raw.docx"

# Clean up any existing result file
rm -f /tmp/task_result.json 2>/dev/null || true

# Kill any existing WPS Writer instances
pkill -f "wps" 2>/dev/null || true
sleep 1

# Launch WPS Writer with the document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/proxy_statement_raw.docx > /dev/null 2>&1 &"

# Wait for WPS window to appear
wait_for_window "WPS Writer" 30

# Maximize and focus the window
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Dismiss dialogs
dismiss_wps_dialogs

# Re-focus just to be safe
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot
echo "Taking initial screenshot..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="