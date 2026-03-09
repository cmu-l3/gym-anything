#!/bin/bash
set -e
echo "=== Setting up Report Pagination & Flow Control Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 1. Create the messy document using python-docx (easier to script)
# We will create it as DOCX then convert to ODT to ensure we start with ODT as requested
cat > /tmp/create_messy_doc.py << 'EOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Helper to add messy spacing
def add_messy_space(n=2):
    for _ in range(n):
        doc.add_paragraph("")

# Title
doc.add_paragraph("Structural Integrity Analysis: Beam-Column Connections")
add_messy_space(3)

# Section 1
doc.add_heading("1. Introduction", level=1)
add_messy_space(1)
doc.add_paragraph(
    "The structural integrity of steel moment frames relies heavily on the performance "
    "of beam-column connections during seismic events. Recent failures in the Northridge "
    "earthquake have prompted a re-evaluation of standard welded flange-bolted web connections."
)
add_messy_space(2)

doc.add_paragraph(
    "This report analyzes the stress distribution in reduced beam section (RBS) connections "
    "under cyclic loading conditions. The objective is to verify that the plastic hinge forms "
    "away from the column face, thereby protecting the connection integrity."
)
add_messy_space(3)

# Section 2 - Force a bad page break scenario by filling text
doc.add_heading("2. Methodology", level=1)
add_messy_space(1)
doc.add_paragraph(
    "We employed a finite element analysis (FEA) using ABAQUS/Standard. The model utilizes "
    "C3D8R solid elements with a mesh refinement of 5mm in the critical connection region. "
    "Material properties were modeled using a combined isotropic/kinematic hardening rule "
    "to simulate cyclic plasticity."
)
add_messy_space(2)

# Filler text to push next heading to bottom of page
for i in range(12):
    doc.add_paragraph(
        f"filler text line {i}: The boundary conditions were applied to simulate a cantilever "
        "setup, with the column fixed at the base and displacement applied at the beam tip. "
        "Load protocols followed the AISC 341-16 seismic provisions."
    )
    add_messy_space(1)

# Stranded Heading (Orphaned Heading)
doc.add_heading("2.1 Mesh Convergence", level=2)
# No text after this, forcing it to be potentially stranded if near bottom
add_messy_space(1)

doc.add_paragraph(
    "A convergence study was conducted with mesh sizes ranging from 20mm down to 2mm. "
    "The results indicated that the 5mm mesh provided an optimal balance between "
    "computational cost and accuracy. Stress singularities at the re-entrant corners "
    "were handled by local elastic material definitions."
)
add_messy_space(3)

# Section 3
doc.add_heading("3. Results and Discussion", level=1)
add_messy_space(1)
doc.add_paragraph(
    "The von Mises stress distribution clearly shows the formation of the plastic hinge "
    "within the reduced section of the beam, approximately 150mm from the column face. "
    "This confirms the efficacy of the RBS design."
)
add_messy_space(2)

doc.add_paragraph(
    "However, residual stresses from the welding process were found to contribute "
    "significantly to the initial yield state. Future work should incorporate "
    "thermal-structural coupled analysis to account for these effects."
)

doc.save("/tmp/structural_analysis_draft.docx")
EOF

# Run the python script
python3 /tmp/create_messy_doc.py

# Convert DOCX to ODT using LibreOffice headless
# This ensures the agent gets a native ODT file to work with
echo "Converting to ODT..."
libreoffice --headless --convert-to odt --outdir /home/ga/Documents /tmp/structural_analysis_draft.docx

# Set ownership
chown ga:ga /home/ga/Documents/structural_analysis_draft.odt

# 2. Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer /home/ga/Documents/structural_analysis_draft.odt > /dev/null 2>&1 &"
fi

# 3. Wait for window and maximize
wait_for_window "LibreOffice Writer" 60 || wait_for_window "structural_analysis" 60
sleep 5

WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="