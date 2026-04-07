#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up HACCP Plan Tables Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

kill_calligra_processes
rm -f /home/ga/Documents/haccp_plan.odt
rm -f /home/ga/Desktop/haccp_formatting_guide.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# ------------------------------------------------------------------
# Create the formatting guide
# ------------------------------------------------------------------
cat > /home/ga/Desktop/haccp_formatting_guide.txt << 'EOF'
FDA HACCP DOCUMENT FORMATTING REQUIREMENTS
Applicability: Juice Processing Facilities (21 CFR Part 120)

1. COVER PAGE
- Title must be "HACCP PLAN" (bold, font size 16pt or larger)
- Facility name ("SunPure Juice Processing LLC") must be centered and bold
- Facility address and other cover page metadata should be centered

2. HEADINGS
- All main HACCP Principle sections and major document sections must use the "Heading 1" style.
- Subsections within principles (e.g., Product Profile, Intended Use, Hazard Evaluation) must use the "Heading 2" style.

3. REQUIRED TABLES
The plain-text data lines in the document must be converted into three properly structured tables:

A. Hazard Analysis Table
- Structure: 6 columns (Process Step | Hazard Type | Hazard Description | Significance | Justification | Preventive Measure)
- Content: Must contain all 8 process steps.

B. CCP Monitoring Table
- Structure: 6 columns (CCP# | Critical Limit | Monitoring Procedure | Frequency | Responsible Person | Corrective Action)
- Content: Must contain the 3 identified CCPs.

C. Verification Schedule Table
- Structure: 4 columns (Activity | Frequency | Responsible Person | Records)
- Content: Must contain the 5 verification activities.

All tables should be clearly formatted (header rows in bold are recommended but not strictly required).

4. BODY TEXT
- All standard paragraph text must be justified alignment.
- Font size must be at least 11pt.
EOF
chown ga:ga /home/ga/Desktop/haccp_formatting_guide.txt

# ------------------------------------------------------------------
# Create the unformatted HACCP plan using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Cover Page Block
add_paragraph("HACCP PLAN")
add_paragraph("SunPure Juice Processing LLC")
add_paragraph("4200 Citrus Grove Road, Lakeland, FL 33801")
add_paragraph("HACCP Plan Number: HACCP-SPJ-2025-003")
add_paragraph("Effective Date: March 15, 2026")
add_paragraph("Prepared By: Quality Assurance Team")
add_paragraph("Approved By: Plant Manager")
add_paragraph("")

# Section
add_paragraph("Process Description")
add_paragraph("Product Profile")
add_paragraph(
    "SunPure Juice Processing operates a modern citrus processing facility producing "
    "100% pasteurized orange and grapefruit juices. The products are extracted, "
    "pasteurized, and chilled on-site, with continuous Brix and pH monitoring."
)
add_paragraph("Intended Use")
add_paragraph(
    "The pasteurized juice products are intended for general public consumption, "
    "including highly susceptible populations. Products are distributed under "
    "refrigerated conditions (34-38°F) to retail and wholesale food establishments."
)
add_paragraph("")

add_paragraph("Process Flow Description")
add_paragraph(
    "The manufacturing process consists of the following consecutive steps: "
    "1. Receiving of fresh fruit, 2. Initial washing, 3. Sorting and grading, "
    "4. Extraction, 5. Filtration, 6. Pasteurization, 7. Filling and packaging, "
    "8. Cold storage and distribution."
)
add_paragraph("")

add_paragraph("Hazard Analysis (Principle 1)")
add_paragraph("Hazard Evaluation")
add_paragraph(
    "The hazard analysis was conducted considering biological, chemical, and "
    "physical hazards at each step of the manufacturing process according to "
    "FDA Juice HACCP Hazards and Controls Guidance."
)
add_paragraph("Hazard Analysis Data:")
add_paragraph("Process Step: 1. Receiving | Hazard Type: Chemical | Hazard Description: Pesticide residues | Significance: Low | Justification: Supplier guarantees | Preventive Measure: Approved supplier program")
add_paragraph("Process Step: 2. Washing | Hazard Type: Biological | Hazard Description: Surface pathogens (Salmonella) | Significance: High | Justification: Historical crop data | Preventive Measure: Antimicrobial wash (CCP-1)")
add_paragraph("Process Step: 3. Sorting | Hazard Type: Physical | Hazard Description: Extraneous matter | Significance: Low | Justification: Visually inspected | Preventive Measure: Employee training")
add_paragraph("Process Step: 4. Extraction | Hazard Type: Biological | Hazard Description: Pathogen ingress | Significance: Low | Justification: Enclosed system | Preventive Measure: SSOPs")
add_paragraph("Process Step: 5. Filtration | Hazard Type: Physical | Hazard Description: Metal fragments | Significance: High | Justification: Equipment wear | Preventive Measure: In-line screen (CCP-2)")
add_paragraph("Process Step: 6. Pasteurization | Hazard Type: Biological | Hazard Description: Pathogen survival (Salmonella, E. coli) | Significance: High | Justification: Required 5-log reduction | Preventive Measure: Thermal pasteurization (CCP-3)")
add_paragraph("Process Step: 7. Filling | Hazard Type: Biological | Hazard Description: Post-process contamination | Significance: Low | Justification: Enclosed hygienic filler | Preventive Measure: GMPs")
add_paragraph("Process Step: 8. Cold Storage | Hazard Type: Biological | Hazard Description: Spoilage organism growth | Significance: Low | Justification: Temperature controlled | Preventive Measure: Refrigeration logs")
add_paragraph("")

add_paragraph("CCP Determination (Principle 2)")
add_paragraph("Justification of CCPs")
add_paragraph(
    "Based on the hazard analysis, three Critical Control Points (CCPs) were "
    "identified to eliminate or reduce significant hazards to acceptable levels. "
    "These include the antimicrobial wash step (CCP-1), the in-line filtration "
    "screen (CCP-2), and the thermal pasteurization step (CCP-3)."
)
add_paragraph("")

add_paragraph("Critical Limits (Principle 3)")
add_paragraph("CCP Monitoring Data:")
add_paragraph("CCP#: CCP-1 (Wash) | Critical Limit: Minimum 200 ppm peracetic acid | Monitoring Procedure: Chemical titration | Frequency: Every 2 hours | Responsible Person: QA Technician | Corrective Action: Adjust dosing, re-wash fruit")
add_paragraph("CCP#: CCP-2 (Screen) | Critical Limit: Screen intact, no tears | Monitoring Procedure: Visual inspection | Frequency: End of each shift | Responsible Person: Production Supervisor | Corrective Action: Replace screen, hold product from shift")
add_paragraph("CCP#: CCP-3 (Pasteurization) | Critical Limit: 72°C for 15 seconds | Monitoring Procedure: Continuous temperature chart | Frequency: Continuous | Responsible Person: Pasteurizer Operator | Corrective Action: Auto flow-diversion, hold product")
add_paragraph("")

add_paragraph("Monitoring Procedures (Principle 4)")
add_paragraph(
    "Monitoring equipment must be calibrated regularly. Operators are required "
    "to document all monitoring activities on designated HACCP logs in real-time. "
    "Falsification of monitoring records is grounds for immediate termination."
)
add_paragraph("")

add_paragraph("Corrective Actions (Principle 5)")
add_paragraph(
    "When a deviation from a critical limit occurs, corrective action must be "
    "taken immediately to regain control of the process and ensure no adulterated "
    "product enters commerce. All affected product must be segregated and placed "
    "on QA hold pending evaluation."
)
add_paragraph("")

add_paragraph("Verification Procedures (Principle 6)")
add_paragraph("Verification Schedule Data:")
add_paragraph("Activity: Thermometer calibration | Frequency: Daily before startup | Responsible Person: QA Technician | Records: Calibration Log")
add_paragraph("Activity: Chart recorder review | Frequency: Daily | Responsible Person: QA Manager | Records: Pasteurizer Chart")
add_paragraph("Activity: Direct observation of monitoring | Frequency: Weekly | Responsible Person: QA Manager | Records: Verification Log")
add_paragraph("Activity: Finished product testing (Micro) | Frequency: Weekly | Responsible Person: External Lab | Records: COA")
add_paragraph("Activity: Comprehensive HACCP plan review | Frequency: Annually | Responsible Person: HACCP Team | Records: Meeting Minutes")
add_paragraph("")

add_paragraph("Record-Keeping (Principle 7)")
add_paragraph(
    "Records must be maintained for a minimum of 2 years for refrigerated products "
    "per 21 CFR Part 120. All critical records must be reviewed and signed by a "
    "trained QA manager within 7 days of generation."
)

doc.save("/home/ga/Documents/haccp_plan.odt")
PYEOF

chown ga:ga /home/ga/Documents/haccp_plan.odt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/haccp_plan.odt" "/tmp/calligra.log"

# Wait for Calligra to load and focus it
sleep 5
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot showing the raw state
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="