#!/bin/bash
# setup_task.sh - STEM Exam Equation Formatting
set -e

echo "=== Setting up STEM Exam Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Generate the draft exam using python-docx first (easier programmatic generation)
# then convert to ODT (required for native Formula Editor support)
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Header
head = doc.add_heading('Calculus I - Midterm Exam', 0)
head.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph("Time Limit: 90 Minutes")
doc.add_paragraph("Instructions: Show all work. Use standard mathematical notation.")
doc.add_paragraph("_" * 50)

# Question 1
doc.add_heading('Question 1: Algebra Review', level=1)
p1 = doc.add_paragraph("Solve for x in the equation 2x² + 5x - 3 = 0 using the general quadratic formula:")
p1_ph = doc.add_paragraph("[INSERT QUADRATIC FORMULA]")
for run in p1_ph.runs:
    run.bold = True
    run.font.color.rgb = RGBColor(255, 0, 0)  # Red to make it obvious
p1_ph.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("Show your steps below:")
doc.add_paragraph("\n\n")

# Question 2
doc.add_heading('Question 2: Differentiation', level=1)
p2 = doc.add_paragraph("State the formal limit definition of the derivative f'(x):")
p2_ph = doc.add_paragraph("[INSERT DERIVATIVE DEFINITION]")
for run in p2_ph.runs:
    run.bold = True
    run.font.color.rgb = RGBColor(255, 0, 0)
p2_ph.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("Use this definition to find the derivative of f(x) = x².")
doc.add_paragraph("\n\n")

# Question 3
doc.add_heading('Question 3: Integration', level=1)
p3 = doc.add_paragraph("Evaluate the following definite integral using the Fundamental Theorem of Calculus:")
p3_ph = doc.add_paragraph("[INSERT DEFINITE INTEGRAL]")
for run in p3_ph.runs:
    run.bold = True
    run.font.color.rgb = RGBColor(255, 0, 0)
p3_ph.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("Explain the geometric interpretation of this result.")

doc.save("/tmp/temp_draft.docx")
PYEOF

# Convert DOCX to ODT using LibreOffice headless
# We want ODT because OLE Math Objects work best natively in ODT format
echo "Converting draft to ODT format..."
libreoffice --headless --convert-to odt --outdir /home/ga/Documents /tmp/temp_draft.docx > /dev/null 2>&1

mv /home/ga/Documents/temp_draft.odt /home/ga/Documents/calculus_midterm_draft.odt
rm /tmp/temp_draft.docx
chown ga:ga /home/ga/Documents/calculus_midterm_draft.odt

# Launch LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/calculus_midterm_draft.odt > /tmp/writer.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "calculus_midterm" 30

# Maximize and focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Zoom to 100% (Ctrl+1 usually, or just ensure visible)
    # This helps VLM see the content clearly
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="