#!/bin/bash
set -e

echo "=== Setting up Academic Manuscript Typesetting task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
sudo -u ga mkdir -p /home/ga/Documents/TextDocuments

# Generate the raw unformatted manuscript using Python
cat << 'EOF' > /tmp/generate_raw_doc.py
import sys
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Add all content as plain paragraphs
paragraphs = [
    "Atmospheric Escape and Evolution of Close-in Exoplanets",
    "Jane Doe, John Smith",
    "We present a comprehensive model of atmospheric escape for close-in exoplanets. Our simulations indicate that extreme UV radiation drives significant mass loss over gigayear timescales, particularly for sub-Neptune mass planets, creating a distinct radius valley.",
    "1. Introduction",
    "The discovery of thousands of exoplanets has revealed a distinct lack of intermediate-sized planets, known as the radius valley. This gap is theorized to result from photoevaporation.",
    "2. Methodology",
    "We utilize a 1D hydrodynamic escape model coupled with a stellar evolution track. The boundary conditions are set at the optical photosphere where the energy deposition from the host star is maximized.",
    "3. Results",
    "Our baseline model reproduces the observed radius gap. We also present a table of simulated planets and their physical properties demonstrating the mass-radius correlation after 5 Gyrs.",
    "Table 1 Data:",
    "Planet, Mass (M_Earth), Radius (R_Earth), Equilibrium Temp (K)",
    "Kepler-11b, 1.9, 1.8, 800",
    "Kepler-11c, 2.9, 2.87, 700",
    "HD 209458b, 220, 15.1, 1450",
    "4. Conclusion",
    "Atmospheric escape remains a dominant mechanism shaping the demographics of short-period exoplanets, confirming theories of thermal mass loss."
]

for text in paragraphs:
    p = doc.add_paragraph(text)
    # Apply raw, uniform, unstyled formatting
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    for run in p.runs:
        run.font.name = 'Calibri'
        run.font.size = Pt(11)
        run.bold = False
        run.italic = False

doc.save('/home/ga/Documents/TextDocuments/manuscript_raw.docx')
EOF

# Run the python script to create the file
python3 /tmp/generate_raw_doc.py
chown ga:ga /home/ga/Documents/TextDocuments/manuscript_raw.docx

# Ensure ONLYOFFICE is not already running
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
sleep 2

# Launch ONLYOFFICE Document Editor with the raw file
echo "Starting ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors /home/ga/Documents/TextDocuments/manuscript_raw.docx > /tmp/onlyoffice.log 2>&1 &"

# Wait for ONLYOFFICE window to appear
echo "Waiting for ONLYOFFICE window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE"; then
        echo "ONLYOFFICE window detected."
        break
    fi
    sleep 1
done

# Allow UI to settle
sleep 3

# Maximize and focus ONLYOFFICE window
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="