#!/bin/bash
set -e
echo "=== Setting up ESA Report Sections Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Create the draft ESA report using python-docx
# This generates a realistic, flat document with no sections/styles
echo "Generating draft document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Helper to add text
def add_para(text, bold=False, size=11, align=None):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = "Liberation Serif"
    run.font.size = Pt(size)
    run.bold = bold
    if align:
        p.alignment = align
    return p

# --- COVER PAGE CONTENT (Plain text, agent must isolate this) ---
add_para("PHASE I ENVIRONMENTAL SITE ASSESSMENT", bold=True, size=16, align=WD_ALIGN_PARAGRAPH.CENTER)
doc.add_paragraph("")
add_para("Former Kerrigan Manufacturing Facility", bold=True, size=14, align=WD_ALIGN_PARAGRAPH.CENTER)
add_para("1847 Industrial Parkway, Millbrook, NJ 07850", size=12, align=WD_ALIGN_PARAGRAPH.CENTER)
doc.add_paragraph("")
add_para("Project No. ESA-2024-0472", size=12, align=WD_ALIGN_PARAGRAPH.CENTER)
doc.add_paragraph("")
doc.add_paragraph("")
doc.add_paragraph("")
add_para("Prepared for:", bold=True)
add_para("Tri-State Redevelopment Partners, LLC")
doc.add_paragraph("")
add_para("Prepared by:", bold=True)
add_para("Greenfield Environmental Associates")
add_para("400 Corporate Blvd, Suite 100")
add_para("Hamilton, NJ 08690")
doc.add_paragraph("")
add_para("Date: November 15, 2024")
doc.add_page_break()

# --- BODY CONTENT (Plain text, agent must apply styles) ---

# Executive Summary
add_para("Executive Summary", bold=True, size=12) # Should be Heading 1
add_para("Greenfield Environmental Associates has performed a Phase I Environmental Site Assessment (ESA) in conformance with the scope and limitations of ASTM Practice E1527-21 of the property located at 1847 Industrial Parkway, Millbrook, New Jersey (the 'Subject Property').")
add_para("The Subject Property consists of approximately 4.5 acres of land improved with a 45,000 square foot light industrial building constructed circa 1968. Historical records indicate the property was used for metal fabrication and plating operations from 1968 to 1995, and subsequent warehousing/distribution to present.")
add_para("Recognized Environmental Conditions (RECs) identified include: (1) Historical use of chlorinated solvents (TCE) in metal degreasing operations; (2) A former 10,000-gallon heating oil UST removed in 1992 with incomplete closure documentation.")

# Introduction
add_para("Introduction", bold=True, size=12) # Should be Heading 1
add_para("Purpose", bold=True, size=11) # Should be Heading 2
add_para("The purpose of this Phase I ESA is to identify, to the extent feasible pursuant to the process described herein, recognized environmental conditions in connection with the property.")
add_para("Scope and Limitations", bold=True, size=11) # Should be Heading 2
add_para("This assessment was conducted in accordance with ASTM E1527-21. Limitations include physical obstructions (snow cover, dense vegetation) and data gaps regarding pre-1940 usage.")

# Site Description
add_para("Site Description", bold=True, size=12) # Should be Heading 1
add_para("Location and Legal Description", bold=True, size=11) # Should be Heading 2
add_para("The Subject Property is located at 40°45'12\" N, 74°23'05\" W. Legal Description: Block 402, Lot 5 on the Tax Map of the Township of Millbrook.")
add_para("Current Use and Conditions", bold=True, size=11) # Should be Heading 2
add_para("The site is currently occupied by 'Logistics Plus', a shipping fulfillment center. The building is heated by natural gas. No active manufacturing processes were observed.")

# Records Review
add_para("Records Review", bold=True, size=12) # Should be Heading 1
add_para("Environmental Database Review", bold=True, size=11) # Should be Heading 2
add_para("A review of federal and state databases revealed the following:")
add_para("- NPL: Not listed")
add_para("- CERCLIS: Not listed")
add_para("- RCRA-GEN: The facility is listed as a Small Quantity Generator (SQG) under EPA ID NJD987654321. No violations reported in the last 5 years.")
add_para("Historical Use Records", bold=True, size=11) # Should be Heading 2
add_para("Sanborn Fire Insurance Maps from 1970 and 1985 depict the building labeled as 'Kerrigan Metal Works - Plating & Finishing'.")

# Site Reconnaissance
add_para("Site Reconnaissance", bold=True, size=12) # Should be Heading 1
add_para("Methodology", bold=True, size=11) # Should be Heading 2
add_para("A site visit was performed on November 10, 2024, by Mr. John Smith, Environmental Professional.")
add_para("Observations", bold=True, size=11) # Should be Heading 2
add_para("Visual inspection of the concrete slab in the former plating area revealed minor staining and sealed floor drains. No stressed vegetation was observed on the exterior.")

# Findings
add_para("Findings and Opinions", bold=True, size=12) # Should be Heading 1
add_para("We have identified the historical metal plating operations and potential solvent use as a Recognized Environmental Condition (REC). The lack of closure documentation for the 1992 UST removal represents a Controlled Recognized Environmental Condition (CREC).")

# Conclusions
add_para("Conclusions and Recommendations", bold=True, size=12) # Should be Heading 1
add_para("We have performed a Phase I Environmental Site Assessment in conformance with the scope and limitations of ASTM Practice E1527-21. This assessment has revealed evidence of recognized environmental conditions.")
add_para("We recommend a limited Phase II ESA (subsurface soil and groundwater investigation) to evaluate the potential for chlorinated solvent impact in the former plating area.")

# References
add_para("References", bold=True, size=12) # Should be Heading 1
add_para("1. ASTM International. Standard Practice for Environmental Site Assessments: Phase I Environmental Site Assessment Process (ASTM E1527-21).")
add_para("2. EDR Radius Map Report with GeoCheck, Inquiry Number 5551234.2s, dated November 01, 2024.")
add_para("3. New Jersey Department of Environmental Protection (NJDEP) Data Miner.")
doc.add_page_break()

# --- DATA SECTION (Agent should make this Landscape) ---
add_para("Site Maps and Data Tables", bold=True, size=12) # Should be Heading 1
add_para("[NOTE: This section contains wide data tables and should be oriented Landscape]", size=10)
doc.add_paragraph("")

# Add a wide table to justify landscape
table = doc.add_table(rows=5, cols=6)
table.style = 'Table Grid'
hdr_cells = table.rows[0].cells
headers = ["Well ID", "Sample Date", "Depth (ft)", "TCE (ug/L)", "PCE (ug/L)", "Vinyl Chloride (ug/L)"]
for i, h in enumerate(headers):
    hdr_cells[i].text = h

data = [
    ["MW-1", "10/25/2024", "15.5", "ND", "ND", "ND"],
    ["MW-2", "10/25/2024", "14.2", "5.2", "1.1", "ND"],
    ["MW-3", "10/25/2024", "16.0", "124.0", "15.3", "2.1"],
    ["MW-4", "10/25/2024", "15.1", "45.6", "4.2", "ND"]
]
for row_data in data:
    row_cells = table.add_row().cells
    for i, val in enumerate(row_data):
        row_cells[i].text = val

doc.add_paragraph("")
add_para("Figure 1: Site Location Map (Placeholder)")
doc.add_paragraph("[MAP IMAGE PLACEHOLDER - WIDE FORMAT]")
doc.add_page_break()

# --- APPENDICES (Agent should keep/return to Portrait) ---
add_para("Appendices", bold=True, size=12) # Should be Heading 1
add_para("Appendix A: Site Photographs")
add_para("Appendix B: Historical Topographic Maps")
add_para("Appendix C: Regulatory Database Report")
add_para("Appendix D: Qualifications of Environmental Professional")

doc.save("/home/ga/Documents/esa_draft.docx")
print("Created ESA draft document")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/esa_draft.docx
chmod 666 /home/ga/Documents/esa_draft.docx

# Start LibreOffice Writer with the draft
echo "Starting LibreOffice Writer..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/esa_draft.docx &"
fi

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "esa_draft" 60

# Maximize and focus
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Focusing window ID: $WID"
    focus_window "$WID"
    sleep 1
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss sidebar if open (F11 toggles styles, maybe we want it open?)
# Let's open the Styles sidebar as a hint/help
safe_xdotool ga :1 key F11
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="