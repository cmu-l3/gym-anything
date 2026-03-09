#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Spec Cross-Reference Repair Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate the source document with specific "traps" (manual text references)
# We use python-docx to ensure the document structure is valid and headings exist.
python3 << 'PYEOF'
import os
try:
    from docx import Document
    from docx.shared import Pt
    from docx.enum.text import WD_BREAK
except ImportError:
    print("python-docx not found, checking environment...")
    exit(1)

doc = Document()

# Title Page
doc.add_heading('Functional Specification', 0)
doc.add_paragraph('Project: MediTrack Patient Management System')
doc.add_paragraph('Version: 2.4 (DRAFT)')
doc.add_paragraph('Date: October 14, 2025')
doc.add_page_break()

# Section 1
doc.add_heading('1. Introduction', level=1)
doc.add_heading('1.1 Purpose', level=2)
doc.add_paragraph('The purpose of this document is to define the functional requirements for the MediTrack system.')

doc.add_heading('1.2 Scope', level=2)
p = doc.add_paragraph('This module covers patient intake and data processing. For detailed admission workflows, refer to ')
# THE TRAP: Manual text that looks like a reference but isn't
run = p.add_run('Section 3.1 Patient Admission')
# Make it look normal (no special formatting)
p.add_run('.')

doc.add_paragraph('This integration supports HL7 v2.5 messaging standards.')
doc.add_page_break()

# Section 2 (Filler to ensure page numbers differ)
doc.add_heading('2. System Architecture', level=1)
doc.add_paragraph('The system relies on a microservices architecture. ' * 20)
doc.add_page_break()

# Section 3
doc.add_heading('3. Clinical Workflows', level=1)

# Target Heading 1
doc.add_heading('3.1 Patient Admission', level=2)
doc.add_paragraph('The admission process begins when a patient presents at the front desk. Users must collect demographic data.')
doc.add_paragraph('Mandatory fields: Name, DOB, Insurance Provider.')
doc.add_page_break()

# Section 4
doc.add_heading('4. Security & Compliance', level=1)
p = doc.add_paragraph('All data encryption must adhere to the ')
# THE TRAP 2: Manual text page reference (deliberately vague/wrong)
p.add_run('compliance protocols found on page 8.')
doc.add_paragraph('Audit logs must be maintained for 7 years.')
doc.add_page_break()

# Section 5 - Target Heading 2
doc.add_heading('5. Compliance Standards', level=1)
doc.add_paragraph('HIPAA compliance requires strict access controls.')
doc.add_paragraph('AES-256 encryption is standard for data at rest.')

output_path = "/home/ga/Documents/functional_spec_draft.docx"
doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/functional_spec_draft.docx
chmod 666 /home/ga/Documents/functional_spec_draft.docx

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/functional_spec_draft.docx > /tmp/writer.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
if wait_for_window "LibreOffice Writer" 60; then
    echo "Writer window found."
elif wait_for_window "functional_spec" 10; then
    echo "Document window found."
else
    echo "WARNING: Writer window not detected, but process is running."
fi

# Maximize window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="