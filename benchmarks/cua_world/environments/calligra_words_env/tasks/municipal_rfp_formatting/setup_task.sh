#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Municipal RFP Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
kill_calligra_processes
rm -f /home/ga/Documents/smart_parking_rfp.odt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the unformatted RFP document using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title area
add_paragraph("City of Grand Oak")
add_paragraph("Request for Proposal: Smart City Parking Management System")
add_paragraph("RFP No. 2026-04")
add_paragraph("")

# Section 1
add_paragraph("1.0 General Information")
add_paragraph("The City of Grand Oak is seeking proposals from qualified vendors to provide a comprehensive Smart City Parking Management System. This system will modernize the city's downtown parking infrastructure, improving the experience for residents, visitors, and local businesses.")
add_paragraph("All proposals must be submitted no later than October 15, 2026 at 2:00 PM local time. Late submissions will not be accepted under any circumstances.")
add_paragraph("")

# Section 2
add_paragraph("2.0 Scope of Work")
add_paragraph("The selected vendor will be responsible for the design, procurement, installation, and ongoing maintenance of smart parking sensors, mobile application interfaces, and an administrative dashboard for the City's Parking Authority.")
add_paragraph("")

# Section 3
add_paragraph("3.0 Schedule of Events")
add_paragraph("RFP Issuance: September 1, 2026")
add_paragraph("Pre-Proposal Conference: September 15, 2026")
add_paragraph("Deadline for Questions: October 1, 2026")
add_paragraph("Proposal Due Date: October 15, 2026")
add_paragraph("")

# Section 4
add_paragraph("4.0 Mandatory Technical Requirements")
add_paragraph("The system must support real-time occupancy tracking for up to 5,000 parking spaces.")
add_paragraph("The system must integrate with the existing City enforcement application via REST API.")
add_paragraph("The vendor must provide 24/7 technical support with a 2-hour SLA.")
add_paragraph("The solution must be fully PCI-DSS compliant for payment processing.")
add_paragraph("Hardware components must operate in temperatures ranging from -20°C to 50°C.")
add_paragraph("")

# Section 5
add_paragraph("5.0 Evaluation Criteria")
add_paragraph("Proposals will be evaluated by a selection committee based on technical merit (40%), total cost of ownership (30%), vendor experience and references (20%), and implementation timeline (10%).")
add_paragraph("")

# Section 6
add_paragraph("6.0 Submission Instructions")
add_paragraph("Vendors must submit one (1) electronic copy via the City Procurement Portal and three (3) physical copies to the Office of the City Clerk. Please ensure the Vendor Response Matrix is completed in full.")
add_paragraph("")
add_paragraph("Authorized Signature")

doc.save("/home/ga/Documents/smart_parking_rfp.odt")
PYEOF

chown ga:ga /home/ga/Documents/smart_parking_rfp.odt

# Launch Calligra Words with the document
echo "Launching Calligra Words..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/smart_parking_rfp.odt >/dev/null 2>&1 &"

# Wait for window and maximize
wait_for_window "Calligra Words" 15
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any stray dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="