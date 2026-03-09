#!/bin/bash
# setup_task.sh - Clinical Protocol Formatting

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Clinical Protocol Formatting Task ==="

# 1. Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# 3. Generate the messy draft document using Python
# We use python-docx to generate a file with specific "bad" formatting
# (Liberation Serif, 12pt, 1.25" margins, single spacing, no styles)
cat << 'PYEOF' | python3
import os
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Set "bad" margins (1.25 inches)
sections = doc.sections
for section in sections:
    section.top_margin = Inches(1.25)
    section.bottom_margin = Inches(1.25)
    section.left_margin = Inches(1.25)
    section.right_margin = Inches(1.25)

# Helper to add messy text
def add_messy_para(text, bold=False, italic=False, align=None):
    p = doc.add_paragraph()
    if align == 'center':
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    elif align == 'right':
        p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    
    # Force single spacing and 0pt after (messy state)
    p.paragraph_format.line_spacing = 1.0
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.space_before = Pt(0)
    
    run = p.add_run(text)
    run.font.name = 'Liberation Serif'
    run.font.size = Pt(12)
    run.bold = bold
    run.italic = italic
    return p

# --- Content Generation (Based on SSC 2021 Guidelines) ---

# Title (Left aligned, plain bold - needs centering)
add_messy_para("Sepsis Management Clinical Protocol", bold=True)
add_messy_para("")

# Section 1
add_messy_para("Purpose and Scope", bold=True)
add_messy_para("This protocol outlines the standardized approach for the early identification and management of sepsis and septic shock in adult patients at Memorial Regional Hospital. It is based on the Surviving Sepsis Campaign (SSC) International Guidelines 2021.")
add_messy_para("")

# Section 2
add_messy_para("Definitions", bold=True)
add_messy_para("Sepsis: Life-threatening organ dysfunction caused by a dysregulated host response to infection. Organ dysfunction can be identified as an acute change in total SOFA score >= 2 points consequent to the infection.")
add_messy_para("Septic Shock: A subset of sepsis in which underlying circulatory and cellular/metabolic abnormalities are profound enough to substantially increase mortality. Identified by a clinical construct of sepsis with persisting hypotension requiring vasopressors to maintain MAP >= 65 mmHg and having a serum lactate level > 2 mmol/L despite adequate volume resuscitation.")
add_messy_para("")

# Section 3
add_messy_para("Screening and Early Identification", bold=True)
add_messy_para("Effective screening is critical for early recognition. The hospital utilizes the National Early Warning Score (NEWS2) integrated into the EHR.")
add_messy_para("qSOFA (Quick SOFA)", bold=True, italic=True)
add_messy_para("Criteria include respiratory rate >= 22/min, altered mentation, or systolic blood pressure <= 100 mmHg. While qSOFA should not be used as a single screening tool due to low sensitivity, positive findings should prompt full assessment.")
add_messy_para("")

# Section 4
add_messy_para("Initial Resuscitation", bold=True)
add_messy_para("Sepsis and septic shock are medical emergencies. Treatment and resuscitation should begin immediately.")
add_messy_para("Hour-1 Bundle", bold=True, italic=True)
add_messy_para("1. Measure lactate level. Remeasure if initial lactate is > 2 mmol/L.")
add_messy_para("2. Obtain blood cultures before administering antibiotics.")
add_messy_para("3. Administer broad-spectrum antibiotics.")
add_messy_para("4. Begin rapid administration of 30 mL/kg crystalloid for hypotension or lactate >= 4 mmol/L.")
add_messy_para("5. Apply vasopressors if hypotensive during or after fluid resuscitation to maintain MAP >= 65 mmHg.")
add_messy_para("")

# Section 5
add_messy_para("Antimicrobial Therapy", bold=True)
add_messy_para("Administration Timing", bold=True, italic=True)
add_messy_para("For patients with probable septic shock, administer antimicrobials immediately, ideally within 1 hour of recognition. For patients with possible sepsis without shock, rapid assessment should occur, and antimicrobials should be administered within 3 hours if concern for infection persists.")
add_messy_para("Empiric Selection", bold=True, italic=True)
add_messy_para("Empiric broad-spectrum therapy with one or more antimicrobials to cover all likely pathogens should be started. Selection depends on patient history, clinical status, and local resistance patterns.")
add_messy_para("")

# Section 6
add_messy_para("Hemodynamic Management", bold=True)
add_messy_para("Fluid Resuscitation", bold=True, italic=True)
add_messy_para("For patients with sepsis-induced hypoperfusion or septic shock, suggested initial fluid resuscitation is 30 mL/kg of intravenous crystalloid fluid. Balanced crystalloids (e.g., Lactated Ringer's) are suggested over normal saline.")
add_messy_para("Vasopressor Therapy", bold=True, italic=True)
add_messy_para("Norepinephrine is the first-line vasopressor. If norepinephrine is not available, epinephrine or dopamine can be used as an alternative, though dopamine should be used with caution. Target Mean Arterial Pressure (MAP) is 65 mmHg.")
add_messy_para("")

# Section 7
add_messy_para("Organ Support", bold=True)
add_messy_para("Mechanical Ventilation", bold=True, italic=True)
add_messy_para("For adults with sepsis-induced ARDS, we suggest using a low tidal volume ventilation strategy (6 mL/kg predicted body weight) over a high tidal volume strategy.")
add_messy_para("Renal Replacement Therapy", bold=True, italic=True)
add_messy_para("For adults with sepsis and acute kidney injury, we suggest using either continuous or intermittent renal replacement therapy, as no difference in outcomes has been demonstrated.")
add_messy_para("")

# Section 8
add_messy_para("Monitoring and Reassessment", bold=True)
add_messy_para("Patients should be reassessed frequently to evaluate response to treatment. Dynamic measures of fluid responsiveness (e.g., passive leg raise, stroke volume variation) are preferred over static variables.")
add_messy_para("")

# References
add_messy_para("References", bold=True)
add_messy_para("Evans L, Rhodes A, Alhazzani W, et al. Surviving Sepsis Campaign: International Guidelines for Management of Sepsis and Septic Shock 2021. Intensive Care Med. 2021;47(11):1181-1247.")
add_messy_para("Singer M, Deutschman CS, Seymour CW, et al. The Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3). JAMA. 2016;315(8):801-810.")
add_messy_para("Rhodes A, Evans LE, Alhazzani W, et al. Surviving Sepsis Campaign: International Guidelines for Management of Sepsis and Septic Shock: 2016 Update. Intensive Care Med. 2017;43(3):304-377.")
add_messy_para("Seymour CW, Liu VX, Iwashyna TJ, et al. Assessment of Clinical Criteria for Sepsis: For the Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3). JAMA. 2016;315(8):762-774.")

file_path = "/home/ga/Documents/sepsis_protocol_draft.docx"
doc.save(file_path)
print(f"Created messy draft at {file_path}")
PYEOF

# 4. Set permissions
chown ga:ga /home/ga/Documents/sepsis_protocol_draft.docx
chmod 666 /home/ga/Documents/sepsis_protocol_draft.docx

# 5. Launch LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/sepsis_protocol_draft.docx > /tmp/writer.log 2>&1 &"

# 6. Wait for window and maximize
wait_for_window "LibreOffice Writer" 60
sleep 2

WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing Writer window ($WID)..."
    focus_window "$WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    
    # Dismiss any "Tip of the Day" or "What's New"
    sleep 2
    DISPLAY=:1 xdotool key Escape
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="