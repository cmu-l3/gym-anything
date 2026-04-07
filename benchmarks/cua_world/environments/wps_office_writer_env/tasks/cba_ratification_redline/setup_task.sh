#!/bin/bash
set -euo pipefail

echo "=== Setting up CBA Ratification Redline Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents

# Create the raw draft document
python3 << 'PYEOF'
import os
from docx import Document
from docx.shared import Pt

doc = Document()

# Add unformatted text
doc.add_paragraph("Article 1: Recognition")
doc.add_paragraph("Section 1.1")
doc.add_paragraph("The Employer recognizes the Union as the sole and exclusive bargaining agent for all production and maintenance employees.")

doc.add_paragraph("Article 2: Management Rights")
doc.add_paragraph("Section 2.1")
doc.add_paragraph("Except as specifically abridged by this Agreement, all rights to manage the operations are vested exclusively in the Employer.")

doc.add_paragraph("Article 3: Grievance Procedure")
doc.add_paragraph("Section 3.1")
doc.add_paragraph("Grievances shall be processed in the following manner:")
doc.add_paragraph("Step One: The employee shall discuss the grievance with their immediate supervisor within five (5) working days.")
doc.add_paragraph("Step Two: If unresolved, the grievance shall be reduced to writing and submitted to the Department Manager.")
doc.add_paragraph("Step Three: If unresolved, the Union Grievance Committee shall meet with the Plant Manager.")
doc.add_paragraph("Step Four: If unresolved, the dispute may be submitted to binding arbitration.")

doc.add_paragraph("Article 5: Overtime")
doc.add_paragraph("Section 5.3")
doc.add_paragraph("The Employer shall provide advance notice of mandatory overtime. Employees will receive advance notice of twenty-four (24) hours forty-eight (48) hours prior to the scheduling of mandatory weekend overtime.")

doc.add_paragraph("Article 7: Wages")
doc.add_paragraph("Section 7.1")
doc.add_paragraph("The following wage scale shall be in effect for the duration of this Agreement:")
# Comma-separated data for the agent to convert to a table
doc.add_paragraph("Classification, Current Rate, Year 1 Rate, Year 2 Rate, Year 3 Rate")
doc.add_paragraph("Assembler I, $18.00, $19.00, $19.50, $20.00")
doc.add_paragraph("Assembler II, $20.00, $21.50, $22.25, $23.00")
doc.add_paragraph("Maintenance Tech, $25.00, $27.00, $28.00, $29.00")
doc.add_paragraph("Quality Inspector, $22.00, $23.50, $24.25, $25.00")

doc.add_paragraph("Article 11: Health & Welfare")
doc.add_paragraph("Section 11.2")
doc.add_paragraph("Employees shall contribute 15% 18% of the monthly premium for health insurance coverage. The Employer shall pay the remaining balance.")

doc.add_paragraph("Article 12: Duration")
doc.add_paragraph("Section 12.1")
doc.add_paragraph("This Agreement shall be effective upon ratification and remain in full force and effect for three (3) years.")

doc.save("/home/ga/Documents/CBA_Draft.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/CBA_Draft.docx

# Clean any existing task files
rm -f /home/ga/Documents/CBA_Tentative_Agreement.docx 2>/dev/null || true

# Start WPS Writer with the document
echo "Starting WPS Writer..."
pkill -f "wps" || true
sleep 2

su - ga -c "DISPLAY=:1 wps /home/ga/Documents/CBA_Draft.docx &"
sleep 5

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "CBA_Draft"; then
        echo "WPS Writer window detected"
        break
    fi
    sleep 1
done

WID=$(DISPLAY=:1 wmctrl -l | grep -i "wps" | head -n 1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="