#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Clinical Protocol Formatting Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/adult_sepsis_protocol_draft.odt
rm -f /home/ga/Documents/adult_sepsis_protocol_FINAL.odt
rm -f /home/ga/Desktop/protocol_style_guide.txt

# ------------------------------------------------------------------
# Create the style guide
# ------------------------------------------------------------------
cat > /home/ga/Desktop/protocol_style_guide.txt << 'EOF'
HOSPITAL CLINICAL POLICY FORMATTING GUIDELINES

1. Document Title: Must be Centered, Bold, and at least 16pt font size.
2. Main Sections: Use "Heading 1" style for the 6 primary sections.
3. Equipment: Format the required equipment list as a Bulleted List.
4. Interventions: Format the step-by-step interventions as a Numbered List.
5. Clinical Alerts: Any paragraph starting with "CLINICAL ALERT:" must be indented on BOTH the left and right sides by at least 0.5 inches (or 1.27 cm) to make it stand out. The text of the alert must also be Bold.
6. Body Text: All standard paragraph text (not headings, lists, or alerts) should be Justified.
EOF
chown ga:ga /home/ga/Desktop/protocol_style_guide.txt

# ------------------------------------------------------------------
# Create the unformatted Sepsis Protocol using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("ADULT SEVERE SEPSIS AND SEPTIC SHOCK PROTOCOL")
add_paragraph("")
add_paragraph("Purpose")
add_paragraph("To provide evidence-based guidelines for the early identification and aggressive management of adult patients presenting with severe sepsis or septic shock in the Emergency Department and inpatient units. Early recognition and protocolized care significantly reduce mortality.")
add_paragraph("")
add_paragraph("Definitions")
add_paragraph("Sepsis is defined as life-threatening organ dysfunction caused by a dysregulated host response to infection. Septic shock is a subset of sepsis in which underlying circulatory and cellular/metabolic abnormalities are profound enough to substantially increase mortality.")
add_paragraph("")
add_paragraph("Required Equipment")
add_paragraph("Peripheral IV access kits (18 gauge or larger)")
add_paragraph("Central venous catheterization kit")
add_paragraph("Crystalloid IV fluids (Lactated Ringer's or Normal Saline)")
add_paragraph("Point-of-care lactate meter or phlebotomy supplies")
add_paragraph("Blood culture bottles (aerobic and anaerobic)")
add_paragraph("Broad-spectrum intravenous antibiotics")
add_paragraph("")
add_paragraph("Assessment Criteria")
add_paragraph("Evaluate patients for suspected infection and two or more qSOFA criteria: altered mental status (GCS < 15), systolic blood pressure <= 100 mmHg, or respiratory rate >= 22 breaths per minute. A serum lactate > 2 mmol/L is also indicative of tissue hypoperfusion.")
add_paragraph("")
add_paragraph("Interventions")
add_paragraph("Measure lactate level. Remeasure lactate if initial lactate is elevated (> 2 mmol/L) within 2-4 hours.")
add_paragraph("Obtain blood cultures before administering antibiotics. Draw at least two sets of blood cultures (aerobic and anaerobic) from different anatomical sites.")
add_paragraph("CLINICAL ALERT: Do not delay antibiotic administration while waiting for blood culture results if obtaining cultures will significantly delay therapy (e.g., greater than 45 minutes).")
add_paragraph("Administer broad-spectrum intravenous antibiotics. Antibiotic selection should be based on suspected source of infection and local antibiogram data.")
add_paragraph("Begin rapid administration of 30 mL/kg crystalloid fluid for hypotension or lactate >= 4 mmol/L. Fluid resuscitation should be completed within 3 hours.")
add_paragraph("CLINICAL ALERT: Patients with heart failure or end-stage renal disease require careful fluid resuscitation and frequent assessment for signs of volume overload during bolus administration.")
add_paragraph("Apply vasopressors if hypotension occurs during or after fluid resuscitation to maintain a mean arterial pressure (MAP) >= 65 mmHg. Norepinephrine is the first-line vasopressor.")
add_paragraph("")
add_paragraph("Documentation")
add_paragraph("All interventions, vital signs, reassessments, and the time of protocol initiation (Time Zero) must be documented in the electronic health record within the Sepsis Flowsheet.")
add_paragraph("")

doc.save("/home/ga/Documents/adult_sepsis_protocol_draft.odt")
PYEOF

chown ga:ga /home/ga/Documents/adult_sepsis_protocol_draft.odt

# Launch Calligra Words with the document
launch_calligra_document "/home/ga/Documents/adult_sepsis_protocol_draft.odt"

# Wait for application to load
wait_for_window "Calligra Words" 30

# Maximize and focus the window
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot showing the unformatted document
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="