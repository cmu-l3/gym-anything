#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Zoning Ordinance Format Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

sudo -u ga mkdir -p /home/ga/Documents

# Generate the raw input document
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Main Title (Raw, unformatted)
doc.add_paragraph("ARTICLE X: TRANSIT-ORIENTED DEVELOPMENT (TOD) DISTRICT")

# Section 1
doc.add_paragraph("Section 1. Purpose")
doc.add_paragraph(
    "The purpose of the Transit-Oriented Development (TOD) District is to encourage a mix of "
    "residential, commercial, and employment uses within walking distance of high-capacity transit "
    "stations. This district promotes pedestrian-friendly urban design, reduces reliance on "
    "single-occupancy vehicles, and maximizes the public investment in transit infrastructure."
)

# Section 2
doc.add_paragraph("Section 2. Applicability")
doc.add_paragraph(
    "The standards in this Article apply to all properties located within one-half mile of "
    "designated light rail and bus rapid transit stations as identified on the Official Zoning Map."
)

# Section 3
doc.add_paragraph("Section 3. Definitions")
doc.add_paragraph(
    "For the purposes of this Article, the following terms shall apply:\n\n"
    "Transit Station Area: The geographic area within a 0.5-mile radius of a designated transit station platform.\n\n"
    "Active Floor Area: The ground-floor space of a building designed for retail, restaurant, or personal service uses.\n\n"
    "Pedestrian-Oriented Facade: A building frontage that includes a primary entrance, minimum 60% transparency (windows), and weather protection.\n\n"
    "Shared Parking: A parking management strategy where two or more distinct land uses share a common parking facility to maximize efficiency."
)

# Section 4 - Prose to be converted into a table
doc.add_paragraph("Section 4. Permitted Uses")
doc.add_paragraph(
    "The following uses are regulated within the TOD District. "
    "Use Category: Residential, Specific Use: Multi-Family Dwelling, Status: Permitted (P), Standards: Sec 5.A. "
    "Use Category: Commercial, Specific Use: Retail Sales, Status: Permitted (P), Standards: Sec 5.B. "
    "Use Category: Commercial, Specific Use: Professional Office, Status: Permitted (P), Standards: None. "
    "Use Category: Industrial, Specific Use: Light Manufacturing, Status: Conditional (C), Standards: Sec 5.C."
)

# Section 5
doc.add_paragraph("Section 5. Development Standards")
doc.add_paragraph(
    "A. Residential density shall be a minimum of 30 dwelling units per acre.\n"
    "B. Retail uses must occupy the ground floor of any building facing a primary arterial street.\n"
    "C. Light manufacturing is only permitted if entirely enclosed and generating no external noise or emissions."
)

# Section 6
doc.add_paragraph("Section 6. Parking")
doc.add_paragraph(
    "Minimum off-street parking requirements are reduced by 50% for all properties within the TOD District. "
    "Maximum parking ratios shall not exceed 1.5 spaces per residential unit or 2.5 spaces per 1,000 sq ft of commercial space."
)

doc.save("/home/ga/Documents/tod_ordinance_raw.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/tod_ordinance_raw.docx
sudo chmod 644 /home/ga/Documents/tod_ordinance_raw.docx

# Kill any existing WPS instances
pkill -f "wps" 2>/dev/null || true
sleep 1

# Launch WPS Writer with the raw document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/tod_ordinance_raw.docx &"

# Wait for WPS window to appear
echo "Waiting for WPS window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "WPS Writer\|tod_ordinance_raw"; then
        echo "WPS window detected"
        break
    fi
    sleep 1
done

# Dismiss dialogs, focus and maximize
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

WID=$(DISPLAY=:1 wmctrl -l | grep -i "WPS Writer\|tod_ordinance_raw" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 1
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="