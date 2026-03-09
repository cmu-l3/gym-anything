#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Syllabus Accessibility Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate simple dummy images (BMP format is easiest to generate without extra libs)
# We need a 'Logo' and a 'Chart'
python3 << 'IMG_EOF'
import struct

def create_bmp(filename, width, height, color):
    # BMP Header
    file_size = 54 + width * height * 3
    # B, M, size, reserved1, reserved2, offset
    header = struct.pack('<2sIHHI', b'BM', file_size, 0, 0, 54)
    # Header info: size, w, h, planes, bpp, compression, img_size, xres, yres, clr_used, clr_imp
    info_header = struct.pack('<IIIHHIIIIII', 40, width, height, 1, 24, 0, width * height * 3, 0, 0, 0, 0)
    
    # Pixel data (BGR format)
    b, g, r = color
    pixel = struct.pack('BBB', b, g, r)
    row_padding = (4 - (width * 3) % 4) % 4
    data = (pixel * width + b'\x00' * row_padding) * height
    
    with open(filename, 'wb') as f:
        f.write(header)
        f.write(info_header)
        f.write(data)

# Blue square for logo
create_bmp('/tmp/logo.bmp', 100, 100, (255, 0, 0))
# Red rectangle for chart
create_bmp('/tmp/chart.bmp', 200, 150, (0, 0, 255))
print("Created dummy images")
IMG_EOF

# Create the inaccessible draft document
python3 << 'DOC_EOF'
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# 1. Main Title (Manual formatting, NO heading style)
p = doc.add_paragraph()
run = p.add_run("CS101: Introduction to Computer Science")
run.font.name = "Liberation Sans"
run.font.size = Pt(24)
run.bold = True
run.color.rgb = RGBColor(0, 51, 102)  # Dark blue
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

# 2. Logo Image (No Alt Text)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run()
run.add_picture('/tmp/logo.bmp', width=Inches(1.0))

# 3. Course Description (Manual formatting, NO heading style)
p = doc.add_paragraph()
run = p.add_run("Course Description")
run.font.name = "Liberation Sans"
run.font.size = Pt(16)
run.bold = True
run.color.rgb = RGBColor(0, 51, 102)

doc.add_paragraph(
    "This course provides a comprehensive introduction to the fundamental concepts "
    "of computer science. Topics include algorithms, data structures, software "
    "engineering, and the ethical implications of computing technologies."
)

# 4. Learning Objectives
p = doc.add_paragraph()
run = p.add_run("Learning Objectives")
run.font.name = "Liberation Sans"
run.font.size = Pt(16)
run.bold = True
run.color.rgb = RGBColor(0, 51, 102)

doc.add_paragraph("- Understand basic algorithmic thinking")
doc.add_paragraph("- Write simple programs in Python")
doc.add_paragraph("- Analyze computational complexity")

# 5. Grading Scale (Table without header row property)
p = doc.add_paragraph()
run = p.add_run("Grading Scale")
run.font.name = "Liberation Sans"
run.font.size = Pt(16)
run.bold = True
run.color.rgb = RGBColor(0, 51, 102)

table = doc.add_table(rows=5, cols=2)
table.style = 'Table Grid'
# Row 1 (Header visually, but not semantically)
cell = table.cell(0, 0)
cell.text = "Component"
cell.paragraphs[0].runs[0].bold = True
cell = table.cell(0, 1)
cell.text = "Weight"
cell.paragraphs[0].runs[0].bold = True

# Data rows
data = [("Exams", "40%"), ("Labs", "30%"), ("Project", "20%"), ("Participation", "10%")]
for i, (comp, weight) in enumerate(data):
    table.cell(i+1, 0).text = comp
    table.cell(i+1, 1).text = weight

doc.add_paragraph("")

# 6. Chart Image (No Alt Text)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run()
run.add_picture('/tmp/chart.bmp', width=Inches(3.0))
p = doc.add_paragraph("Figure 1: Grade Distribution")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

# 7. Weekly Schedule
p = doc.add_paragraph()
run = p.add_run("Weekly Schedule")
run.font.name = "Liberation Sans"
run.font.size = Pt(16)
run.bold = True
run.color.rgb = RGBColor(0, 51, 102)

doc.add_paragraph("Week 1: Introduction & Ethics")
doc.add_paragraph("Week 2: Variables & Control Flow")
doc.add_paragraph("Week 3: Functions & Modules")

# 8. Academic Integrity
p = doc.add_paragraph()
run = p.add_run("Academic Integrity")
run.font.name = "Liberation Sans"
run.font.size = Pt(16)
run.bold = True
run.color.rgb = RGBColor(0, 51, 102)

doc.add_paragraph(
    "Plagiarism and cheating are serious offenses. Students found violating the "
    "code of conduct will receive a failing grade for the assignment."
)

doc.save('/home/ga/Documents/CS101_Syllabus_Draft.docx')
print("Draft document created successfully.")
DOC_EOF

# Clean up temp images
rm /tmp/logo.bmp /tmp/chart.bmp

# Set permissions
chown ga:ga /home/ga/Documents/CS101_Syllabus_Draft.docx
chmod 666 /home/ga/Documents/CS101_Syllabus_Draft.docx

# Launch LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/CS101_Syllabus_Draft.docx > /tmp/writer_task.log 2>&1 &"

# Wait for Writer to start
wait_for_process "soffice" 15
wait_for_window "CS101" 60 || wait_for_window "LibreOffice Writer" 30

# Maximize and focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any initial dialogs
safe_xdotool ga :1 key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="