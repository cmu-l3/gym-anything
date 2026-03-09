#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Outline Numbering Handbook Task ==="

# 1. Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Generate the "messy" unformatted employee handbook
# We use python-docx to create a file where headings are just "Normal" style
# with manual bold/size formatting, simulating a manually typed document.
cat > /tmp/create_handbook.py << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()
doc.styles['Normal'].font.name = 'Liberation Serif'
doc.styles['Normal'].font.size = Pt(11)

def add_manual_heading(text, level):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.bold = True
    if level == 1:
        run.font.size = Pt(16) # Looks like H1
    elif level == 2:
        run.font.size = Pt(14) # Looks like H2
    elif level == 3:
        run.font.size = Pt(12) # Looks like H3
    # Note: No style applied, defaults to Normal
    return p

def add_body_text():
    text = (
        "The Company is committed to providing a work environment that is free from "
        "discrimination and harassment. It is our policy to recruit, hire, train, "
        "and promote individuals without regard to race, color, religion, age, sex, "
        "national origin, disability status, genetics, protected veteran status, "
        "sexual orientation, gender identity or expression, or any other characteristic "
        "protected by federal, state or local laws."
    )
    doc.add_paragraph(text)
    doc.add_paragraph("")

# Title
title = doc.add_paragraph("Employee Policy Manual")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.bold = True
    run.font.size = Pt(24)
doc.add_paragraph("")

# Section 1
add_manual_heading("General Employment Policies", 1)
add_manual_heading("Equal Opportunity Employment", 2)
add_body_text()
add_manual_heading("Reasonable Accommodations", 3)
add_body_text()
add_manual_heading("Employment Classifications", 2)
add_body_text()

# Section 2
add_manual_heading("Compensation and Benefits", 1)
add_manual_heading("Pay Structure and Schedule", 2)
add_body_text()
add_manual_heading("Overtime Compensation", 3)
add_body_text()
add_manual_heading("Insurance and Retirement Benefits", 2)
add_body_text()
add_manual_heading("Health Insurance", 3)
add_body_text()
add_manual_heading("Retirement Plans", 3)
add_body_text()

# Section 3
add_manual_heading("Time Off and Leave Policies", 1)
add_manual_heading("Annual Leave", 2)
add_body_text()
add_manual_heading("Sick Leave", 2)
add_body_text()
add_manual_heading("Leave Donation Program", 3)
add_body_text()
add_manual_heading("Family and Medical Leave", 2)
add_body_text()

# Section 4
add_manual_heading("Workplace Conduct and Ethics", 1)
add_manual_heading("Standards of Professional Conduct", 2)
add_body_text()
add_manual_heading("Electronic Communications Policy", 3)
add_body_text()
add_manual_heading("Anti Harassment Policy", 2)
add_body_text()

# Section 5
add_manual_heading("Health Safety and Security", 1)
add_manual_heading("Workplace Safety Program", 2)
add_body_text()
add_manual_heading("Emergency Procedures", 2)
add_body_text()
add_manual_heading("Fire Evacuation Plan", 3)
add_body_text()

# Section 6
add_manual_heading("Separation and Termination", 1)
add_manual_heading("Voluntary and Involuntary Separation", 2)
add_body_text()
add_manual_heading("Return of Company Property", 3)
add_body_text()

doc.save("/home/ga/Documents/employee_handbook.docx")
print("Created /home/ga/Documents/employee_handbook.docx")
PYEOF

python3 /tmp/create_handbook.py
sudo chown ga:ga /home/ga/Documents/employee_handbook.docx
rm /tmp/create_handbook.py

# 4. Launch LibreOffice Writer with the file
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/employee_handbook.docx > /tmp/writer.log 2>&1 &"

# 5. Wait for window and maximize
if ! wait_for_window "LibreOffice Writer" 60; then
    # Sometimes title is just filename
    wait_for_window "employee_handbook" 30 || true
fi

wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    echo "Focusing window $wid"
    focus_window "$wid"
    sleep 1
    # Maximize
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz
    sleep 1
    # Dismiss any first-run dialogs (Esc key)
    safe_xdotool ga :1 key Escape
fi

# 6. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="