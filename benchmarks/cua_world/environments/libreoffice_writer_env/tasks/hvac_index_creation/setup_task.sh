#!/bin/bash
# setup_task.sh — HVAC Index Creation Task
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up HVAC Index Creation Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Create the HVAC Service Manual with python-docx
# This ensures a clean state with specific technical terms present for the agent to find.
echo "Generating HVAC Service Manual..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title
title = doc.add_heading('AirMax 5000 Series Commercial Rooftop Unit', 0)
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
subtitle = doc.add_paragraph('Installation, Operation, and Maintenance Manual')
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_page_break()

# Section 1: System Overview
doc.add_heading('System Overview', level=1)
doc.add_paragraph(
    "The AirMax 5000 is a high-efficiency packaged rooftop unit designed for commercial applications. "
    "The core of the cooling system features a dual-stage scroll Compressor designed for quiet operation "
    "and capacity modulation. Heat rejection is handled by a micro-channel Condenser coil which offers "
    "superior heat transfer properties compared to traditional tube-and-fin designs."
)
doc.add_paragraph(
    "Inside the air handler section, the direct-expansion Evaporator coil absorbs heat from the "
    "conditioned space. The system comes pre-charged with R-410A Refrigerant, which is environmentally "
    "friendly and chlorine-free. Airflow is managed by a variable-speed ECM Blower motor that adjusts "
    "static pressure automatically."
)

# Section 2: Installation Procedures
doc.add_heading('Installation Procedures', level=1)
doc.add_paragraph(
    "Proper installation is critical for optimal performance. Begin by placing the roof curb and "
    "ensuring it is level. Connect high-voltage wiring to the disconnect switch and low-voltage "
    "control wiring to the terminal block. The unit requires a standard 24VAC Thermostat for "
    "operation. Ensure the outdoor air hood is installed to prevent water ingress."
)
doc.add_paragraph(
    "For units equipped with a factory-installed Economizer, verify that the damper linkage moves "
    "freely and the enthalpy sensor is calibrated. The expansion device is a thermostatic "
    "Expansion valve (TXV) located at the evaporator inlet."
)

# Section 3: Preventive Maintenance
doc.add_heading('Preventive Maintenance', level=1)
doc.add_paragraph(
    "Quarterly inspections are recommended. Inspect the condenser coil for debris and clean with "
    "water if necessary. Check the belt tension on the blower assembly (if belt-driven) or verify "
    "rotation on direct-drive units. Inspect the electrical panel for loose connections, specifically "
    "checking the run Capacitor for bulging or oil leaks, as this is a common failure point."
)

# Section 4: Troubleshooting Guide
doc.add_heading('Troubleshooting Guide', level=1)
table = doc.add_table(rows=1, cols=2)
table.style = 'Table Grid'
hdr_cells = table.rows[0].cells
hdr_cells[0].text = 'Symptom'
hdr_cells[1].text = 'Possible Cause'

row = table.add_row().cells
row[0].text = 'Unit does not start'
row[1].text = 'No power, tripped breaker, or open transformer'

row = table.add_row().cells
row[0].text = 'Compressor short cycles'
row[1].text = 'Low Refrigerant charge or high pressure switch trip'

row = table.add_row().cells
row[0].text = 'Insufficient cooling'
row[1].text = 'Dirty Evaporator coil or blocked filter'

doc.add_paragraph("")
doc.add_paragraph(
    "If the Heat exchanger shows signs of cracking or corrosion during heating mode inspection, "
    "the unit must be shut down immediately to prevent carbon monoxide leakage."
)

# Section 5: Component Specifications
doc.add_heading('Component Specifications', level=1)
doc.add_paragraph(
    "Compressor: Scroll type, 2-stage, 208/230V 3-phase.\n"
    "Blower motor: ECM, 3.0 HP, variable speed.\n"
    "Condenser coil: Aluminum micro-channel.\n"
    "Refrigerant: R-410A, factory charge 12.5 lbs.\n"
    "Heat exchanger: Aluminized steel tubular design."
)

# Section 6: Safety Procedures
doc.add_heading('Safety Procedures', level=1)
doc.add_paragraph(
    "Always disconnect electrical power before servicing. When handling Refrigerant, wear safety "
    "glasses and gloves to prevent frostbite. Discharge the Capacitor before touching electrical "
    "components to avoid shock hazard."
)

doc.save("/home/ga/Documents/hvac_service_manual.docx")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/hvac_service_manual.docx
chmod 666 /home/ga/Documents/hvac_service_manual.docx

# Clean up any previous runs
rm -f /home/ga/Documents/hvac_manual_indexed.docx 2>/dev/null || true

# Launch LibreOffice Writer with the document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/hvac_service_manual.docx > /tmp/writer_task.log 2>&1 &"

# Wait for Writer to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    exit 1
fi

# Wait for window
wait_for_window "hvac_service_manual" 60

# Maximize window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="