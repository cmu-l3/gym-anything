#!/bin/bash
set -e
echo "=== Setting up Conference Attendee List Prep Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Document directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Generate the raw data file using python3 and python-docx
# We create a file with ~60 rows of tab-separated text in Portrait mode
echo "Generating raw attendee data..."
cat << 'PYEOF' > /tmp/gen_attendee_data.py
import os
from docx import Document
from docx.shared import Pt, Inches

# Realistic dataset
# Format: Last Name | First Name | Company | Email
data = [
    ("Last Name", "First Name", "Company", "Email"),
    ("Martinez", "Sofia", "Apex Logistics", "s.martinez@apexlog.com"),
    ("Wong", "David", "TechFlow Solutions", "d.wong@techflow.io"),
    ("Schmidt", "Hans", "Summit Financial", "h.schmidt@summitfin.com"),
    ("Johnson", "Emma", "Apex Logistics", "e.johnson@apexlog.com"),
    ("Patel", "Aarav", "Global Health Inc.", "a.patel@globalhealth.org"),
    ("Dubois", "Marie", "Summit Financial", "m.dubois@summitfin.com"),
    ("Kim", "Ji-oon", "TechFlow Solutions", "j.kim@techflow.io"),
    ("Garcia", "Lucas", "BlueSky Aviation", "l.garcia@bluesky.net"),
    ("Smith", "James", "Apex Logistics", "j.smith@apexlog.com"),
    ("Chen", "Wei", "Global Health Inc.", "w.chen@globalhealth.org"),
    ("O'Connor", "Liam", "Summit Financial", "l.oconnor@summitfin.com"),
    ("Ivanov", "Dmitry", "Omega Structures", "d.ivanov@omega.build"),
    ("Sato", "Yuki", "TechFlow Solutions", "y.sato@techflow.io"),
    ("Moreau", "Camille", "BlueSky Aviation", "c.moreau@bluesky.net"),
    ("Andersson", "Erik", "Omega Structures", "e.andersson@omega.build"),
    ("Rossi", "Giulia", "Global Health Inc.", "g.rossi@globalhealth.org"),
    ("Kowalski", "Jan", "Apex Logistics", "j.kowalski@apexlog.com"),
    ("Brown", "Olivia", "Summit Financial", "o.brown@summitfin.com"),
    ("Nakamura", "Hiro", "TechFlow Solutions", "h.nakamura@techflow.io"),
    ("Lopez", "Maria", "BlueSky Aviation", "m.lopez@bluesky.net")
]

# Repeat data to reach ~60 rows to make manual sorting tedious
expanded_data = [data[0]] # Header
for i in range(1, 4):
    for row in data[1:]:
        expanded_data.append(row)

doc = Document()

# Ensure Portrait orientation (default, but explicit is safer)
section = doc.sections[0]
section.page_width = Inches(8.5)
section.page_height = Inches(11)

# Add lines as tab-separated text
for row in expanded_data:
    line = "\t".join(row)
    p = doc.add_paragraph(line)
    p.style.font.name = 'Liberation Serif'
    p.style.font.size = Pt(11)
    # Ensure no extra spacing that might confuse conversion
    p.paragraph_format.space_after = Pt(0)

# Save to documents
output_path = "/home/ga/Documents/attendee_export_raw.docx"
doc.save(output_path)
print(f"Created {output_path} with {len(expanded_data)} lines")
PYEOF

# Execute generator as user ga
su - ga -c "python3 /tmp/gen_attendee_data.py"
rm /tmp/gen_attendee_data.py

# Launch LibreOffice Writer with the file
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/attendee_export_raw.docx > /tmp/writer.log 2>&1 &"

# Wait for window to appear using shared utility
wait_for_window "LibreOffice Writer" 45 || wait_for_window "attendee_export_raw" 20

# Maximize window
DISPLAY=:1 wmctrl -r "LibreOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "attendee_export_raw" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
focus_window "LibreOffice Writer" || focus_window "attendee_export_raw"

# Dismiss any startup dialogs (like "Tip of the Day")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="