#!/bin/bash
set -e
echo "=== Setting up Construction Safety Plan formatting task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Document directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Define source path
SOURCE_DOC="/home/ga/Documents/safety_plan_raw.docx"

# Create the source document using python-docx
# This generates a "messy" raw file with no styles and wrong fonts
python3 << 'PYEOF'
import sys
# Ensure we can import docx
try:
    from docx import Document
    from docx.shared import Pt, Inches
    from docx.enum.text import WD_ALIGN_PARAGRAPH
    from docx.enum.table import WD_TABLE_ALIGNMENT
except ImportError:
    print("python-docx not found, installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "python-docx"])
    from docx import Document
    from docx.shared import Pt, Inches
    from docx.enum.text import WD_ALIGN_PARAGRAPH
    from docx.enum.table import WD_TABLE_ALIGNMENT

doc = Document()

# Set default font to Liberation Serif 10pt (intentionally wrong)
style = doc.styles['Normal']
font = style.font
font.name = 'Liberation Serif'
font.size = Pt(10)

def add_para(text, bold=False):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.bold = bold
    # Explicitly force local formatting to override defaults later
    run.font.name = 'Liberation Serif'
    run.font.size = Pt(10)
    return p

# Title Page content (plain text)
title_para = doc.add_paragraph()
title_run = title_para.add_run('SITE-SPECIFIC SAFETY PLAN')
title_run.bold = True
title_run.font.size = Pt(14)
title_run.font.name = 'Liberation Serif'
title_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

subtitle = doc.add_paragraph()
sub_run = subtitle.add_run('Riverside Commercial Complex — Phase II Foundation and Structural Work')
sub_run.bold = True
sub_run.font.size = Pt(12)
sub_run.font.name = 'Liberation Serif'
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER

add_para('Prepared by: Marcus Rivera, Site Safety Officer')
add_para('Contractor: Pinnacle Construction Group, LLC')
add_para('Project Number: PCG-2024-0847')
add_para('Date: November 15, 2024')
add_para('OSHA Compliance Reference: 29 CFR 1926 Subpart C')
add_para('')

# Section 1
add_para('1. Purpose and Scope', bold=True)
add_para('This Site-Specific Safety Plan establishes the safety and health requirements for all personnel working on the Riverside Commercial Complex Phase II project located at 4200 Industrial Boulevard, Riverside, California. The plan addresses specific hazards identified during pre-construction planning and defines the control measures, training requirements, and emergency procedures necessary to maintain a safe work environment in compliance with OSHA construction standards under 29 CFR 1926.')
add_para('The scope of this plan covers all foundation excavation, concrete placement, structural steel erection, and associated activities from project mobilization through substantial completion. All contractors, subcontractors, vendors, and visitors entering the project site are required to comply with the provisions of this plan. Failure to comply may result in immediate removal from the site and potential contractual penalties as specified in the prime contract safety provisions.')

add_para('1.1 Applicability', bold=True)
add_para('This plan applies to all phases of the Riverside Commercial Complex Phase II construction, including but not limited to: site preparation and grading, deep foundation installation (drilled shafts to 45 feet), mat foundation concrete placement, structural steel erection to 6 stories, metal deck installation, and exterior envelope work. The plan shall be reviewed and updated whenever site conditions change materially, when new subcontractors mobilize, or when incident investigations reveal the need for additional controls.')
add_para('All personnel, including delivery drivers who leave their vehicles, must complete the site-specific safety orientation before entering work areas beyond the designated visitor staging zone. Orientation records shall be maintained in the on-site safety office trailer and are subject to OSHA inspection upon request.')

add_para('1.2 Regulatory References', bold=True)
add_para('This plan has been developed in accordance with the following regulatory and consensus standards: OSHA 29 CFR 1926 (Safety and Health Regulations for Construction), OSHA 29 CFR 1910 (General Industry Standards, applicable sections), ANSI/ASSE A10 Series (Construction and Demolition Safety Requirements), NFPA 241 (Standard for Safeguarding Construction, Alteration, and Demolition Operations), Cal/OSHA Title 8 General Industry Safety Orders, and the Army Corps of Engineers EM 385-1-1 Safety and Health Requirements Manual as referenced in the owner contract specifications.')

# Section 2
add_para('2. Roles and Responsibilities', bold=True)
add_para('Effective safety management requires clearly defined roles and accountability at every level of the project organization. This section establishes the safety responsibilities for key project personnel and defines the authority structure for safety decision-making on the Riverside Commercial Complex project.')

add_para('2.1 Project Manager Duties', bold=True)
add_para('The Project Manager, David Chen, holds ultimate accountability for safety performance on this project. Specific duties include: ensuring adequate budget allocation for safety equipment, training, and personnel; participating in monthly safety committee meetings; reviewing all incident reports within 24 hours of occurrence; authorizing stop-work orders when imminent danger conditions are identified by any competent person on site; ensuring all subcontractor safety submittals are reviewed and approved prior to mobilization; and maintaining communication with the owner representative regarding safety performance metrics.')
add_para('The Project Manager shall ensure that a qualified Site Safety Officer is assigned to the project full-time during all active construction operations. The Project Manager has the authority to remove any worker, supervisor, or subcontractor employee from the site for safety violations after consultation with the Site Safety Officer.')

add_para('2.2 Site Safety Officer Duties', bold=True)
add_para('The Site Safety Officer, Marcus Rivera (CHST, OSHA-500), is responsible for the day-to-day implementation and enforcement of this safety plan. Key responsibilities include: conducting daily site safety inspections and documenting findings; leading weekly toolbox safety talks for all trades; investigating all incidents, near-misses, and first-aid cases within the shift of occurrence; maintaining OSHA 300 logs and supporting documentation; coordinating with subcontractor safety representatives; managing the site safety orientation program; conducting monthly safety audits using the project safety scorecard; and serving as the primary liaison during any OSHA inspection or consultation visit.')
add_para('The Site Safety Officer has stop-work authority over any operation on the project regardless of schedule impact. This authority extends to all prime contractor and subcontractor work activities. Stop-work decisions shall be documented on Form SSO-104 and reported to the Project Manager within one hour.')

# Section 3
add_para('3. Hazard Identification and Risk Assessment', bold=True)
add_para('A comprehensive hazard identification process was conducted during pre-construction planning in accordance with OSHA recommended practices for safety and health programs (OSHA 3885). The assessment was updated following the 60% design review and will be revised at each major phase transition. The identified hazards and their associated risk ratings form the basis for the Job Hazard Analysis matrices in Section 4.')

add_para('3.1 Initial Site Assessment', bold=True)
add_para('The initial site assessment was conducted on September 12-13, 2024, by Marcus Rivera (SSO), a geotechnical engineer from Terrafirm Associates, and representatives from the three major subcontractors (foundation, structural steel, and electrical). The assessment identified the following primary hazard categories: fall hazards from elevation (steel erection to 78 feet), struck-by hazards from crane operations and overhead work, caught-in/between hazards during excavation and foundation work, electrical hazards from temporary power distribution and proximity to existing 12kV overhead lines on the south property boundary, silica dust exposure during concrete cutting operations, and heat illness risk during summer months in the Riverside climate.')
add_para('Soil borings indicate a high water table at approximately 18 feet below grade, requiring dewatering during deep foundation installation. Contaminated soil was not identified in the Phase II Environmental Site Assessment (Terracon Report ESA-2024-0291), but a soil management plan has been prepared as a precautionary measure given the historical industrial use of the adjacent parcel to the east.')

add_para('3.2 Ongoing Hazard Monitoring', bold=True)
add_para('Hazard conditions are monitored continuously through the following mechanisms: daily pre-task planning by each crew foreman documenting the three highest hazards for planned activities, weekly safety inspections by the Site Safety Officer covering all active work areas, monthly crane and rigging equipment inspections by a third-party qualified inspector, continuous air monitoring for silica during concrete cutting operations (using personal sampling pumps with cyclone attachments), daily weather monitoring for heat index values exceeding 90°F (triggering the heat illness prevention protocol), and real-time noise monitoring in areas adjacent to pile driving and concrete breaking operations.')

# Section 4 - JHA Matrix (this is the section that needs landscape)
add_para('4. Job Hazard Analysis Matrix', bold=True)
add_para('The following Job Hazard Analysis matrix summarizes the critical hazards, risk ratings, and control measures for the major work activities on the Riverside Commercial Complex Phase II project. Risk ratings follow the standard 5x5 matrix (Probability × Severity) as defined in ANSI/ASSE Z590.3. Control measures are listed in hierarchy order per OSHA recommended practices. This matrix shall be reviewed during weekly foreman meetings and updated as conditions change.')

# Create the JHA table
table = doc.add_table(rows=9, cols=6)
table.alignment = WD_TABLE_ALIGNMENT.CENTER
table.style = 'Table Grid'

# Header row
headers = ['Task / Activity', 'Hazard Description', 'Probability (1-5)', 'Severity (1-5)', 'Risk Rating', 'Control Measures']
for i, header in enumerate(headers):
    cell = table.rows[0].cells[i]
    cell.text = header
    for paragraph in cell.paragraphs:
        for run in paragraph.runs:
            run.bold = True
            run.font.size = Pt(9)
            run.font.name = 'Liberation Serif'

# Data rows - real JHA content
jha_data = [
    ['Structural steel erection at elevation', 'Falls from elevation, dropped objects', '3', '5', '15 - High', '100% tie-off above 15ft; CDZ procedures; tool lanyards'],
    ['Tower crane operation', 'Struck-by falling loads, power line contact', '2', '5', '10 - High', 'Certified operator; lift plans; 20ft clearance from power lines'],
    ['Excavation for mat foundation', 'Cave-in, engulfment', '3', '5', '15 - High', 'Engineered shoring; benching 1.5H:1V; dewatering'],
    ['Concrete placement', 'Chemical burns, silica exposure', '4', '3', '12 - Med', 'PPE (gloves/boots); wet methods for cutting'],
    ['Temporary electrical', 'Electrocution, arc flash', '2', '5', '10 - High', 'GFCI on all circuits; assured grounding program'],
    ['Welding and cutting', 'Fire, toxic fumes, UV radiation', '3', '4', '12 - Med', 'Hot work permit; fire watch; welding screens; ventilation'],
    ['Material handling', 'Struck-by, musculoskeletal injury', '4', '3', '12 - Med', 'Designated staging; forklift certification; housekeeping'],
    ['Drilling deep shafts', 'Caught-in drill rig, noise', '3', '5', '15 - High', 'Exclusion zones; casing; hearing conservation program'],
]

for row_idx, row_data in enumerate(jha_data, 1):
    for col_idx, cell_text in enumerate(row_data):
        cell = table.rows[row_idx].cells[col_idx]
        cell.text = cell_text
        for paragraph in cell.paragraphs:
            for run in paragraph.runs:
                run.font.size = Pt(9)
                run.font.name = 'Liberation Serif'

add_para('')
add_para('Note: Risk ratings of 15 or above (High) require a task-specific safety briefing before work begins each day.')

# Section 5
add_para('5. Emergency Action Procedures', bold=True)
add_para('Emergency procedures have been developed in coordination with the Riverside Fire Department Station 14. All emergency procedures shall be reviewed during site orientation and posted at the site safety board adjacent to the main entrance gate.')

add_para('5.1 Evacuation Routes and Assembly Points', bold=True)
add_para('Two primary evacuation routes have been established: Route A exits through the main gate to Assembly Point 1, and Route B exits through the emergency gate to Assembly Point 2. Air horns (three blasts) signal immediate evacuation. Headcounts must be conducted within 5 minutes.')

add_para('5.2 Medical Emergency Response', bold=True)
add_para('A minimum of two personnel with current First Aid/CPR/AED certification shall be on site. Call 911 first, then radio the Site Safety Officer on Channel 3. The address is 4200 Industrial Boulevard.')

# Section 6
add_para('6. Safety Training Requirements', bold=True)
add_para('All personnel must complete required training including OSHA 10/30, Fall Protection, and site orientation. Records are maintained in the Pinnacle Safety Management System.')

doc.save('/home/ga/Documents/safety_plan_raw.docx')
print("Source document created successfully")
PYEOF

# Ensure proper ownership
chown ga:ga "$SOURCE_DOC"

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 1

# Launch LibreOffice Writer with the source document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer '$SOURCE_DOC' > /tmp/writer.log 2>&1 &"

# Wait for window to appear
if wait_for_window "LibreOffice Writer" 45; then
    echo "Writer window found"
else
    # Fallback check for document title
    wait_for_window "safety_plan_raw" 15 || echo "Warning: Window detection timed out, continuing anyway"
fi

# Maximize the window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any "What's New" or recovery dialogs
    safe_xdotool ga :1 key Escape 2>/dev/null || true
    sleep 0.5
fi

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="