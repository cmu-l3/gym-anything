#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up CERT Pocket Guide Formatting Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
install -d -o ga -g ga /home/ga/Documents
kill_calligra_processes
rm -f /home/ga/Documents/cert_field_guide_draft.odt

# ------------------------------------------------------------------
# Create the unformatted CERT FOG document using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title area
add_paragraph("CERT Field Operations Guide")
add_paragraph("Community Emergency Response Team - District 4")
add_paragraph("Version 2.4 - Official Deployment Copy")
add_paragraph("")
add_paragraph("This guide contains standard operating procedures for CERT volunteers during disaster deployment. Keep this booklet with your deployment gear at all times.")
add_paragraph("")

# Section 1
add_paragraph("Incident Command Structure")
add_paragraph("The Incident Command System (ICS) is the standardized approach to the command, control, and coordination of emergency response. The Incident Commander (IC) is responsible for all aspects of the response.")
add_paragraph("Operations Section: Directs all tactical actions to meet the incident objectives.")
add_paragraph("Planning Section: Collects, evaluates, and displays incident intelligence and information.")
add_paragraph("Logistics Section: Provides adequate services and support to meet all incident needs.")
add_paragraph("Finance/Administration Section: Tracks incident-related costs and personnel records.")
add_paragraph("")

# Section 2
add_paragraph("Search and Rescue Operations")
add_paragraph("1. Sizeup the situation: Gather facts, assess damage, consider probabilities, and assess your situation.")
add_paragraph("2. Search systematically: Use a defined pattern (e.g., bottom-up, top-down, right-wall, left-wall).")
add_paragraph("3. Mark the structure: Use the standard 'X' search marking system on doors/walls to indicate search status and findings.")
add_paragraph("4. Triaging victims: Focus on providing the greatest good for the greatest number in the shortest time.")
add_paragraph("")

# Section 3
add_paragraph("Medical Triage")
add_paragraph("CERT uses the START method (Simple Triage and Rapid Treatment) for adult victims.")
add_paragraph("Immediate (Red): Life-threatening injuries but treatable. RPM check: Respiration >30, Perfusion (Capillary refill >2s), or Mental status (Cannot follow simple commands).")
add_paragraph("Delayed (Yellow): Serious injuries but not immediately life-threatening. Patient is stable.")
add_paragraph("Minor (Green): Walking wounded. Can move out of the hazard zone under their own power.")
add_paragraph("Deceased/Expectant (Black): Not breathing after two attempts to open the airway.")
add_paragraph("")

# Section 4
add_paragraph("Radio Communications")
add_paragraph("Use plain language only. No 10-codes. Ensure radio is fully charged before deployment.")
add_paragraph("Below are the standard frequency assignments for District 4 operations:")
add_paragraph("")
add_paragraph("Channel, Purpose, Frequency")
add_paragraph("Channel 1, Command, 155.750")
add_paragraph("Channel 2, Tactical A, 155.235")
add_paragraph("Channel 3, Tactical B, 155.265")
add_paragraph("Channel 4, Medical, 155.340")
add_paragraph("Channel 5, Logistics, 154.430")
add_paragraph("")

# Section 5
add_paragraph("Hazard Assessment")
add_paragraph("Before initiating any action, responders must evaluate the environment for potential hazards. Look for:")
add_paragraph("- Structural instability or partial collapse")
add_paragraph("- Downed electrical lines or exposed wiring")
add_paragraph("- Natural gas leaks or hazardous material spills")
add_paragraph("- Rising water levels or secondary fire risks")
add_paragraph("If a scene is deemed unsafe, DO NOT ENTER. Report the hazard to the Incident Commander immediately.")

doc.save("/home/ga/Documents/cert_field_guide_draft.odt")
PYEOF

chown ga:ga /home/ga/Documents/cert_field_guide_draft.odt

# Launch Calligra Words with the document
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/cert_field_guide_draft.odt"

# Wait for window and maximize it
if wait_for_window "Calligra Words" 30; then
    WID=$(get_calligra_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="