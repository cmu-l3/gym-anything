#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Chemical Inventory Formatting Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Record task start time
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# Create the draft document using python-docx
# We create a document with deliberately plain text (no sub/superscript)
python3 << 'PYEOF'
import os
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# 1. Document Title
title = doc.add_paragraph("Chemistry Laboratory Chemical Inventory and Safety Reference")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
# Note: Leaving title as Normal style but larger font to distinguish it slightly, 
# but agent isn't asked to change this.
for run in title.runs:
    run.font.size = Pt(14)
    run.bold = True

doc.add_paragraph("Lab Location: Science Hall, Room 304")
doc.add_paragraph("Last Updated: October 2024")
doc.add_paragraph("")

# 2. Section: Compound Inventory (Plain text, agent must make Heading 1)
doc.add_paragraph("Compound Inventory")

# Create Table
table = doc.add_table(rows=1, cols=5)
table.style = 'Table Grid'
hdr_cells = table.rows[0].cells
hdr_cells[0].text = 'Compound Name'
hdr_cells[1].text = 'Formula'
hdr_cells[2].text = 'CAS Number'
hdr_cells[3].text = 'Hazard Class'
hdr_cells[4].text = 'Storage Location'

# Inventory Data
inventory_data = [
    ('Water (reagent grade)', 'H2O', '7732-18-5', 'Non-hazardous', 'Cabinet A-1'),
    ('Sulfuric acid', 'H2SO4', '7664-93-9', 'Corrosive', 'Acid cabinet B-3'),
    ('Carbon dioxide (cylinder)', 'CO2', '124-38-9', 'Simple asphyxiant', 'Gas rack C-1'),
    ('Sodium carbonate', 'Na2CO3', '497-19-8', 'Irritant', 'Shelf D-2'),
    ('Iron(III) oxide', 'Fe2O3', '1309-37-1', 'Non-hazardous', 'Shelf D-4'),
    ('Ammonium nitrate', 'NH4NO3', '6484-52-2', 'Oxidizer/Explosive', 'Isolated E-1'),
    ('Potassium permanganate', 'KMnO4', '7722-64-7', 'Oxidizer', 'Cabinet B-5'),
    ('Calcium hydroxide', 'Ca(OH)2', '1305-62-0', 'Irritant', 'Shelf D-1'),
    ('Acetic acid (glacial)', 'CH3COOH', '64-19-7', 'Flammable/Corrosive', 'Flammable cabinet F-2'),
    ('Phosphoric acid', 'H3PO4', '7664-38-2', 'Corrosive', 'Acid cabinet B-4'),
    ('Hydrochloric acid', 'HCl', '7647-01-0', 'Corrosive', 'Acid cabinet B-2'),
    ('Sodium hydroxide (pellets)', 'NaOH', '1310-73-2', 'Corrosive', 'Base cabinet G-1')
]

for name, formula, cas, hazard, loc in inventory_data:
    row_cells = table.add_row().cells
    row_cells[0].text = name
    row_cells[1].text = formula
    row_cells[2].text = cas
    row_cells[3].text = hazard
    row_cells[4].text = loc

doc.add_paragraph("")

# 3. Section: Ionic Species (Plain text, agent must make Heading 1)
doc.add_paragraph("Common Ionic Species in Laboratory Solutions")
doc.add_paragraph("The following ions are commonly present in prepared stock solutions:")
# Plain text ions - agent must superscript charges
doc.add_paragraph("Cations: Na+, Ca2+, Fe3+")
doc.add_paragraph("Anions: Cl-, SO4 2-, CO3 2-")
doc.add_paragraph("")

# 4. Section: Signal Words (Plain text, agent must make Heading 1)
doc.add_paragraph("Safety Signal Word Reference")

p1 = doc.add_paragraph()
p1.add_run("DANGER").bold = False # Explicitly not bold
p1.add_run(": Indicates a hazardous situation which, if not avoided, will result in death or serious injury.")

p2 = doc.add_paragraph()
p2.add_run("WARNING").bold = False
p2.add_run(": Indicates a hazardous situation which, if not avoided, could result in death or serious injury.")

p3 = doc.add_paragraph()
p3.add_run("CAUTION").bold = False
p3.add_run(": Indicates a hazardous situation which, if not avoided, could result in minor or moderate injury.")
doc.add_paragraph("")

# 5. Section: Emergency (Plain text, agent must make Heading 1)
doc.add_paragraph("Emergency Procedures Summary")
doc.add_paragraph("In case of chemical spill, evacuate the immediate area. For eye contact, rinse at eyewash station for 15 minutes.")

# Save draft
doc.save("/home/ga/Documents/chem_inventory_draft.docx")
print("Created /home/ga/Documents/chem_inventory_draft.docx")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/chem_inventory_draft.docx
chmod 666 /home/ga/Documents/chem_inventory_draft.docx

# Launch LibreOffice Writer with the document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/chem_inventory_draft.docx > /tmp/writer_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Writer" 60 || wait_for_window "chem_inventory_draft" 30

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="