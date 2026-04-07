#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up HR Performance Appraisal Form Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents

# Generate the raw unstructured document using python-docx
python3 << 'PYEOF'
import os
from docx import Document

doc = Document()

# Add unformatted title
doc.add_paragraph("Annual Performance Appraisal")
doc.add_paragraph("")

# Add unformatted employee fields
doc.add_paragraph("Employee Name:")
doc.add_paragraph("Job Title:")
doc.add_paragraph("Department:")
doc.add_paragraph("Manager:")
doc.add_paragraph("Review Date:")
doc.add_paragraph("Evaluation Period:")
doc.add_paragraph("")

# Add unformatted rating scale
doc.add_paragraph("RATING SCALE DEFINITIONS")
doc.add_paragraph("1 = Unacceptable")
doc.add_paragraph("2 = Needs Improvement")
doc.add_paragraph("3 = Meets Expectations")
doc.add_paragraph("4 = Exceeds Expectations")
doc.add_paragraph("5 = Outstanding")
doc.add_paragraph("")

# Add unformatted core competencies (OPM definitions)
doc.add_paragraph("CORE COMPETENCIES")
doc.add_paragraph("Accountability: Holds self and others accountable for measurable high-quality, timely, and cost-effective results. Determines objectives, sets priorities, and delegates work. Accepts responsibility for mistakes. Complies with established control systems and rules.")
doc.add_paragraph("Customer Service: Anticipates and meets the needs of both internal and external customers. Delivers high-quality products and services; is committed to continuous improvement.")
doc.add_paragraph("Decisiveness: Makes well-informed, effective, and timely decisions, even when data are limited or solutions produce unpleasant consequences; perceives the impact and implications of decisions.")
doc.add_paragraph("Flexibility: Is open to change and new information; rapidly adapts to new information, changing conditions, or unexpected obstacles.")
doc.add_paragraph("Integrity/Honesty: Behaves in an honest, fair, and ethical manner. Shows consistency in words and actions. Models high standards of ethics.")
doc.add_paragraph("Interpersonal Skills: Treats others with courtesy, sensitivity, and respect. Considers and responds appropriately to the needs and feelings of different people in different situations.")
doc.add_paragraph("Oral Communication: Makes clear and convincing oral presentations. Listens effectively; clarifies information as needed.")
doc.add_paragraph("Problem Solving: Identifies and analyzes problems; weighs relevance and accuracy of information; generates and evaluates alternative solutions; makes recommendations.")
doc.add_paragraph("")

# Extra unformatted text to be converted
doc.add_paragraph("Future Goals (Goal Description, Success Metrics, Target Date)")
doc.add_paragraph("Please enter 3 goals below.")
doc.add_paragraph("")
doc.add_paragraph("Employee Signature:")
doc.add_paragraph("Date:")
doc.add_paragraph("Manager Signature:")
doc.add_paragraph("Date:")

doc.save("/home/ga/Documents/raw_appraisal_content.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/raw_appraisal_content.docx
sudo chmod 644 /home/ga/Documents/raw_appraisal_content.docx

# Clean up any previous task artifacts
rm -f /home/ga/Documents/formatted_appraisal_form.docx 2>/dev/null || true

# Launch WPS Writer
echo "Starting WPS Office Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/raw_appraisal_content.docx > /dev/null 2>&1 &"

# Wait for window to appear
wait_for_window "WPS Writer" 30

# Maximize and focus the window
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any EULAs or popups
dismiss_wps_dialogs

# Re-focus just in case
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="