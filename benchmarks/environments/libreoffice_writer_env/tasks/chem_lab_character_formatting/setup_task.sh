#!/bin/bash
set -e
echo "=== Setting up Chemistry Lab Report Formatting Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any previous run artifacts
rm -f /home/ga/Documents/lab_report_formatted.docx
rm -f /tmp/original_file_hash.txt
rm -f /tmp/original_text_hash.txt

# Generate the draft document with plain text formulas
# We use python-docx to create a realistic report
echo "Generating draft document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
import os
import hashlib

doc = Document()

# Set up styles
style = doc.styles['Normal']
font = style.font
font.name = 'Liberation Serif'
font.size = Pt(12)

# Title
head = doc.add_heading('Riverside Municipal Water Treatment Facility', 0)
head.alignment = WD_ALIGN_PARAGRAPH.CENTER

sub = doc.add_paragraph('Quarterly Water Quality Analytical Report — Q3 2024')
sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
sub.runs[0].bold = True

doc.add_paragraph('Laboratory Report No. RMW-2024-Q3-047').alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph('')

# 1. Introduction
doc.add_heading('1. Introduction', level=1)
doc.add_paragraph(
    "This report presents analytical results for treated drinking water samples collected "
    "from the Riverside facility. The treatment process employs conventional coagulation "
    "with aluminum sulfate (Al2(SO4)3), followed by filtration and disinfection with "
    "sodium hypochlorite (NaOCl). pH adjustment is performed using calcium hydroxide "
    "(Ca(OH)2) and CO2 injection to maintain stability."
)
doc.add_paragraph(
    "Source water is drawn from the Clearwater River, which receives agricultural runoff "
    "contributing elevated levels of NO3- and SO42- during the growing season. "
    "Historical data show that Ca2+ and Mg2+ concentrations vary seasonally."
)

# 2. Analytical Methods
doc.add_heading('2. Analytical Methods', level=1)
doc.add_paragraph(
    "Dissolved metals (Ca2+, Mg2+, Na+, Fe3+) were determined by ICP-OES following "
    "EPA Method 200.7. Samples were preserved with HNO3 to pH < 2. The method detection "
    "limit for Fe3+ is 5.0 ×10-3 mg/L, and for Ca2+ is 1.0 ×10-2 mg/L."
)
doc.add_paragraph(
    "Anion analysis (Cl-, NO3-, SO42-, HCO3-) was performed by ion chromatography. "
    "Alkalinity as CaCO3 was determined by titration with H2SO4 to a pH 4.5 endpoint."
)

# 3. Results
doc.add_heading('3. Results', level=1)

doc.add_heading('3.1 Major Cations', level=2)
doc.add_paragraph(
    "Calcium (Ca2+): 42.3 mg/L. The Ca2+ concentration reflects limestone geology. "
    "Magnesium (Mg2+): 11.8 mg/L. Combined with Ca2+, total hardness is 156 mg/L as CaCO3."
)
doc.add_paragraph(
    "Sodium (Na+): 18.5 mg/L. Iron (Fe3+): 0.028 mg/L. Iron removal efficiency was 9.7 ×10-1."
)

doc.add_heading('3.2 Major Anions', level=2)
doc.add_paragraph(
    "Nitrate (NO3-): 4.7 mg/L as N. The pilot denitrification study reduced NO3- "
    "with rate constant k = 2.4 ×10-3 per minute."
)
doc.add_paragraph(
    "Sulfate (SO42-): 38.1 mg/L. Reflects Al2(SO4)3 usage. "
    "Bicarbonate (HCO3-): 128 mg/L. Carbonate equilibrium: CO2 + H2O = H2CO3 = H+ + HCO3-."
)

doc.add_heading('3.3 Trace Contaminants', level=2)
doc.add_paragraph(
    "Ammonium (NH4+): 0.05 mg/L. Near detection limit of 3.0 ×10-2 mg/L."
)

# 4. QA/QC
doc.add_heading('4. Quality Assurance', level=1)
doc.add_paragraph(
    "Relative percent difference for duplicates was less than 1.0 ×10-1 (10%)."
)

# Save
out_path = '/home/ga/Documents/lab_report_draft.docx'
doc.save(out_path)

# Calculate content hash for verification (to ensure text isn't deleted)
text_content = '\n'.join([p.text for p in doc.paragraphs])
with open('/tmp/original_text_hash.txt', 'w') as f:
    f.write(hashlib.sha256(text_content.encode('utf-8')).hexdigest())

print(f"Created {out_path}")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/lab_report_draft.docx
chmod 644 /home/ga/Documents/lab_report_draft.docx

# Store file hash for anti-gaming (checking if original is modified)
md5sum /home/ga/Documents/lab_report_draft.docx > /tmp/original_file_hash.txt

# Start LibreOffice Writer
echo "Starting LibreOffice Writer..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer /home/ga/Documents/lab_report_draft.docx > /dev/null 2>&1 &"
fi

# Wait for window
wait_for_window "lab_report_draft" 30

# Maximize window
DISPLAY=:1 wmctrl -r "lab_report_draft" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "lab_report_draft" 2>/dev/null || true

# Dismiss "Tip of the Day" if it appears
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="