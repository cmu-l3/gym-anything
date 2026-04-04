#!/bin/bash
set -e
echo "=== Setting up Maintenance Plan Orientation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create document directory
mkdir -p /home/ga/Documents

# Generate the draft document using python-docx
# This creates a realistic document with a wide table that needs landscape layout
python3 << 'PYEOF'
import os
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# --- Title Page Area ---
title = doc.add_paragraph("Annual Preventive Maintenance Plan — FY 2025")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.bold = True
    run.font.size = Pt(18)

subtitle = doc.add_paragraph("Meridian Tower Office Complex")
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in subtitle.runs:
    run.italic = True
    run.font.size = Pt(14)

doc.add_paragraph("Prepared by: Facilities Management Division").alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("")
doc.add_paragraph("")

# --- Introduction (Portrait) ---
# Currently just bold, needs Heading 1
p = doc.add_paragraph("Introduction")
p.runs[0].bold = True
p.runs[0].font.size = Pt(12)

doc.add_paragraph(
    "This Preventive Maintenance (PM) Plan outlines the scheduled maintenance activities "
    "for the Meridian Tower Office Complex (1200 Commerce Boulevard). The facility comprises "
    "200,000 square feet of Class A office space, 12 floors, 4 primary HVAC zones, and "
    "critical life-safety systems. This plan adheres to BOMA International standards and "
    "ASHRAE 180-2018 Standard Practice for Inspection and Maintenance of Commercial Building HVAC Systems."
)
doc.add_paragraph(
    "Implementation of this plan is mandatory for all facilities staff and contracted service "
    "providers. Deviations must be authorized by the Chief Building Engineer."
)
doc.add_paragraph("")

# --- Equipment Schedule (Needs Landscape) ---
# Currently just bold, needs Heading 1
p = doc.add_paragraph("Equipment Schedule")
p.runs[0].bold = True
p.runs[0].font.size = Pt(12)

doc.add_paragraph("The following equipment requires tracked maintenance intervals:")

# Add a wide table (10 columns)
table = doc.add_table(rows=1, cols=10)
table.style = 'Table Grid'
hdr_cells = table.rows[0].cells
headers = ["Equip ID", "Description", "Building/Zone", "Floor", "Manufacturer", "Model", "Service Interval", "Last Service", "Next Due", "Assigned Tech"]
for i, h in enumerate(headers):
    hdr_cells[i].text = h

# Add 15 rows of realistic data
data = [
    ("AHU-001", "Air Handling Unit - VAV", "Tower A / North", "RF", "Trane", "M-Series Climate Changer", "Quarterly", "2024-12-15", "2025-03-15", "J. Smith"),
    ("AHU-002", "Air Handling Unit - VAV", "Tower A / South", "RF", "Trane", "M-Series Climate Changer", "Quarterly", "2024-12-15", "2025-03-15", "J. Smith"),
    ("CH-001", "Centrifugal Chiller", "Central Plant", "B1", "Carrier", "AquaEdge 19DV", "Monthly", "2025-02-01", "2025-03-01", "Carrier Svc"),
    ("CH-002", "Centrifugal Chiller", "Central Plant", "B1", "Carrier", "AquaEdge 19DV", "Monthly", "2025-02-01", "2025-03-01", "Carrier Svc"),
    ("BLR-001", "Condensing Boiler", "Central Plant", "B1", "Viessmann", "Vitocrossal 300", "Semi-Annual", "2024-10-01", "2025-04-01", "M. Doe"),
    ("BLR-002", "Condensing Boiler", "Central Plant", "B1", "Viessmann", "Vitocrossal 300", "Semi-Annual", "2024-10-01", "2025-04-01", "M. Doe"),
    ("CWP-001", "Condenser Water Pump", "Central Plant", "B1", "Bell & Gossett", "e-1510", "Quarterly", "2024-12-20", "2025-03-20", "M. Doe"),
    ("CWP-002", "Condenser Water Pump", "Central Plant", "B1", "Bell & Gossett", "e-1510", "Quarterly", "2024-12-20", "2025-03-20", "M. Doe"),
    ("EF-001", "Exhaust Fan - Restroom", "Tower A", "RF", "Greenheck", "GB-100", "Annual", "2024-06-15", "2025-06-15", "Staff"),
    ("EF-002", "Exhaust Fan - Garage", "Parking", "P1", "Greenheck", "SQ-160", "Annual", "2024-06-15", "2025-06-15", "Staff"),
    ("GEN-001", "Emergency Generator", "Exterior Pad", "G", "Kohler", "KG100", "Monthly", "2025-02-05", "2025-03-05", "PowerPro"),
    ("ATS-001", "Auto Transfer Switch", "Elec Room", "B1", "ASCO", "Series 300", "Annual", "2024-08-10", "2025-08-10", "PowerPro"),
    ("FA-001", "Fire Alarm Panel", "Lobby", "1", "Simplex", "4100ES", "Annual", "2024-05-20", "2025-05-20", "SimplexGrinnell"),
    ("ELV-001", "Passenger Elevator", "Lobby Bank", "All", "Otis", "Gen2", "Monthly", "2025-02-10", "2025-03-10", "Otis Svc"),
    ("ELV-002", "Passenger Elevator", "Lobby Bank", "All", "Otis", "Gen2", "Monthly", "2025-02-10", "2025-03-10", "Otis Svc")
]

for row_data in data:
    row = table.add_row().cells
    for i, text in enumerate(row_data):
        row[i].text = text

doc.add_paragraph("")

# --- Maintenance Procedures (Portrait) ---
# Currently just bold, needs Heading 1
p = doc.add_paragraph("Maintenance Procedures")
p.runs[0].bold = True
p.runs[0].font.size = Pt(12)

doc.add_paragraph(
    "All maintenance activities must be logged in the CMMS (Computerized Maintenance "
    "Management System) within 24 hours of completion. Technicians are required to "
    "follow Lockout/Tagout (LOTO) procedures per OSHA 29 CFR 1910.147 for all "
    "energized equipment."
)
doc.add_paragraph(
    "Quarterly inspections include belt tension checks, filter changes (MERV 13 or higher), "
    "and coil cleaning. Annual inspections require a full vibration analysis and "
    "thermographic scan of electrical connections."
)
doc.add_paragraph("")

# --- Emergency Contacts (Portrait) ---
# Currently just bold, needs Heading 1
p = doc.add_paragraph("Emergency Contacts")
p.runs[0].bold = True
p.runs[0].font.size = Pt(12)

contacts = [
    "Building Engineer: (555) 010-1111",
    "Security Desk: (555) 010-2222",
    "HVAC Service: (555) 010-3333",
    "Elevator Emergency: (555) 010-4444",
    "Fire Monitoring: (555) 010-5555"
]
for c in contacts:
    doc.add_paragraph(c, style='List Bullet')

doc.save("/home/ga/Documents/maintenance_plan_draft.docx")
PYEOF

# Set ownership
chown ga:ga /home/ga/Documents/maintenance_plan_draft.docx

# Start LibreOffice Writer
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/maintenance_plan_draft.docx > /tmp/writer.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 30 || wait_for_window "maintenance_plan" 30

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    focus_window "$WID"
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="