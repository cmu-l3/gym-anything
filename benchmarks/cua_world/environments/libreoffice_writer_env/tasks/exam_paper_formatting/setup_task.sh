#!/bin/bash
set -e

echo "=== Setting up Exam Paper Formatting Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the raw exam document using python-docx
# We create a messy, unformatted document that needs cleanup
echo "Generating raw exam document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches

doc = Document()

# Set default margins to something incorrect (e.g., 0.5 inch or 1.25 inch)
# to ensure the agent actually changes them to 1.0 inch
for section in doc.sections:
    section.left_margin = Inches(0.5)
    section.right_margin = Inches(0.5)
    section.top_margin = Inches(0.5)
    section.bottom_margin = Inches(0.5)

# Helper to add plain text
def add_line(text):
    p = doc.add_paragraph(text)
    # Force default formatting to ensure it's "raw"
    p.style = doc.styles['Normal']
    if p.runs:
        p.runs[0].font.name = 'Calibri'
        p.runs[0].font.size = Pt(11)

# Title Block (Plain text)
add_line("Westfield Regional High School")
add_line("Biology 101 — Final Examination")
add_line("Fall Semester 2024")
add_line("Time Allowed: 90 minutes | Total Points: 100")
add_line("")

# Instructions
add_line("INSTRUCTIONS: Answer all questions in Part A on the bubble sheet provided. Write answers for Part B and Part C in the examination booklet. Electronic devices are strictly prohibited.")
add_line("")

# Part A
add_line("Part A: Multiple Choice (40 points)")
add_line("1. Which organelle is known as the powerhouse of the cell?")
add_line("   a) Nucleus")
add_line("   b) Mitochondrion")
add_line("   c) Ribosome")
add_line("   d) Endoplasmic Reticulum")
add_line("")
add_line("2. In DNA replication, which enzyme unwinds the double helix?")
add_line("   a) DNA Polymerase")
add_line("   b) Ligase")
add_line("   c) Helicase")
add_line("   d) Primase")
add_line("")
add_line("3. What is the primary product of photosynthesis?")
add_line("   a) Carbon Dioxide")
add_line("   b) Water")
add_line("   c) Glucose")
add_line("   d) Nitrogen")
add_line("")

# Part B
add_line("Part B: Short Answer (30 points)")
add_line("4. Explain the difference between mitosis and meiosis in terms of daughter cells produced.")
add_line("")
add_line("5. Describe the role of messenger RNA (mRNA) in protein synthesis.")
add_line("")
add_line("6. Define 'carrying capacity' in the context of population ecology.")
add_line("")

# Part C
add_line("Part C: Essay Questions (30 points)")
add_line("7. Discuss the theory of natural selection. Include the concepts of variation, heritability, and differential reproductive success.")
add_line("")
add_line("8. Compare and contrast the human circulatory system with the respiratory system. How do they depend on each other?")
add_line("")

# End Marker
add_line("--- END OF EXAMINATION ---")

doc.save("/home/ga/Documents/bio101_final_raw.docx")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/bio101_final_raw.docx
chmod 666 /home/ga/Documents/bio101_final_raw.docx

# Record file hash to ensure agent doesn't just modify this file
md5sum /home/ga/Documents/bio101_final_raw.docx > /tmp/raw_file_hash.txt

# Launch LibreOffice Writer with the raw document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/bio101_final_raw.docx > /tmp/writer_launch.log 2>&1 &"

# Wait for Writer to appear
wait_for_window "LibreOffice Writer" 60 || wait_for_window "bio101" 30

# Maximize the window
DISPLAY=:1 wmctrl -r "LibreOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Dismiss "Tip of the Day" if it appears
safe_xdotool ga :1 key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="