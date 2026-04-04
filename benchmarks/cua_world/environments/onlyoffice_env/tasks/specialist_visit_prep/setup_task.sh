#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Specialist Visit Prep Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy medical notes file
NOTES_PATH="$WORKSPACE_DIR/medical_notes_raw.txt"

cat > "$NOTES_PATH" << 'EOF'
Medications (last updated maybe 3 months ago??):
- Ibuprofen 400mg as needed
- Omeprazole 20mg daily started in March
- Vitamin D 2000 IU (dr said to take this)

Symptoms timeline (from my notes):
Jan 15 2024 - severe headache, lasted 3 days, couldn't work
Feb 2 - another headache, plus nausea this time  
March - started getting them weekly, right side of head
March 20 - saw Dr. Chen, she prescribed the omeprazole thought might be reflux related
April - headaches still happening, now with vision disturbances (seeing spots)
May 5 - ER visit, they did CT scan

Test results:
CT scan (May 5 2024) - "no acute abnormalities" 
Blood work from Feb (Dr. Chen): 
  CBC normal
  Vitamin D was low (15 ng/mL)
  Thyroid function normal
MRI scheduled but not done yet

Previous treatments tried:
- Increased water intake - didn't help
- Eliminated caffeine for 3 weeks - maybe helped a little?
- Tried ibuprofen but doesn't always work
- Omeprazole - no change in headaches

Allergies: Penicillin (rash), latex (mild)

Family history: Mom has migraines, Dad has high blood pressure

Doctor's office said: "Please bring a typed one-page medical summary to your appointment tomorrow. 
The doctor needs to quickly understand your history - we only have 15 minutes scheduled."
EOF

chown ga:ga "$NOTES_PATH"
echo "✅ Medical notes created at: $NOTES_PATH"

# Create the starter document with basic instruction
DOC_PATH="$WORKSPACE_DIR/specialist_summary.docx"

cat > /tmp/create_medical_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add a brief instruction at the top
para = doc.add_paragraph("Medical History Summary for Specialist")
para.runs[0].bold = True
para.runs[0].font.size = Pt(16)

doc.add_paragraph("")
doc.add_paragraph("Instructions: Organize the information from medical_notes_raw.txt into clear sections below.")
doc.add_paragraph("")
doc.add_paragraph("[Your formatted summary goes here]")
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Document template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_medical_doc.py
python3 /tmp/create_medical_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document template created at: $DOC_PATH"

# Also create a desktop shortcut to the notes file for easy access
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/VIEW_MEDICAL_NOTES.txt" << 'EOF'
Raw medical notes are available at:
/home/ga/Documents/TextDocuments/medical_notes_raw.txt

You can open it with:
- File manager: Go to Documents/TextDocuments
- Text editor: gedit, nano, or any editor
- Or reference it while working on your summary

Task: Create a professional one-page medical summary in specialist_summary.docx
EOF

chown ga:ga "$DESKTOP_DIR/VIEW_MEDICAL_NOTES.txt"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_medical_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_medical_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Specialist Visit Prep Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  Source: /home/ga/Documents/TextDocuments/medical_notes_raw.txt (unorganized medical notes)"
echo "  Target: /home/ga/Documents/TextDocuments/specialist_summary.docx (your formatted summary)"
echo ""
echo "📋 Required Sections (format with bold headers):"
echo "  1. Current Medications (with dosages)"
echo "  2. Chief Complaint (main symptom)"
echo "  3. Symptom Timeline (chronological)"
echo "  4. Test Results (with dates)"
echo "  5. Treatments Tried"
echo "  6. Allergies (IMPORTANT!)"
echo "  7. Family History"
echo ""
echo "✅ Formatting requirements:"
echo "  - Section headers must be BOLD"
echo "  - At least one header should be larger font (14pt+)"
echo "  - Include specific medications: Ibuprofen, Omeprazole with dosages"
echo "  - Include timeline dates (Jan, Feb, March, April, May)"
echo "  - List BOTH allergies: Penicillin and latex"
echo "  - Keep it to approximately one page"
echo ""
echo "💾 Save when done: Ctrl+S"