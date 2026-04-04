#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Dementia Observation Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw notes text file
RAW_NOTES_PATH="$WORKSPACE_DIR/mom_observations_raw.txt"

cat > "$RAW_NOTES_PATH" << 'EOF'
FAMILY NOTES - MOM'S BEHAVIORAL CHANGES

From Tom (brother): "Friday 1/12 around 9am - went to visit mom, found stove burner on with empty pot. She said she forgot she was making tea. This is the 3rd time this month."

From Sarah (sister): "January 8th evening - Mom called me crying, asking when Dad's funeral is. I had to remind her he passed in 2019. She was very distressed and didn't remember our conversation after 10 minutes."

My notes 1/15: Tuesday afternoon visit - Mom thought it was Sunday. Asked if we were going to church. Had to reorient her 3 times during the visit. More confused than usual.

Tom again 1/10: "Went grocery shopping with mom. She got lost in the store (has shopped there for 20 years). Found her in the cereal aisle looking panicked. Said she couldn't remember what she came for."

My notes 1/18: Morning visit - Found mail unopened for several days. Bills mixed with junk mail. One bill is overdue. Mom said she "was going to get to it" but seemed overwhelmed by the pile.

Sarah 1/14: "Called mom around 7pm. She was very agitated and suspicious, accused me of moving her things. This is new - she's never been paranoid before. Lasted about 30 mins then she calmed down and apologized."

My notes 1/20: Visited at 6:30pm - Mom was pacing, very restless and agitated. Kept saying she needed to "get home" even though she was at home. Sundowning getting worse?

Tom 1/17: "Took mom to Dr. Chang (PCP) for regular checkup. In the waiting room she asked me 4 times why we were there. She used to be so sharp."

Sarah 1/21: "Morning call (10am) - mom sounded clear and normal. Had normal conversation about the weather and her garden. Good days still happen!"

My notes 1/22: Found mom wearing winter coat inside, said she was cold. Thermostat was at 72. She also had trouble working the microwave - needed step by step help with something she's done thousands of times.

Additional context:
- Patient: Margaret Chen, DOB: 03/15/1950 (age 74)
- Diagnosis: Early-stage Alzheimer's disease (diagnosed 8 months ago)
- Current medication: Donepezil 10mg daily
- Next neurology appointment: February 5, 2024
- Lives independently in her own home
EOF

chown ga:ga "$RAW_NOTES_PATH"

echo "✅ Raw notes created at: $RAW_NOTES_PATH"

# Create the initial document template with instructions
DOC_PATH="$WORKSPACE_DIR/mom_behavioral_log_neuro.docx"

cat > /tmp/create_dementia_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, Inches
import sys

doc = Document()

# Set margins
sections = doc.sections
for section in sections:
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)

# Add title
title = doc.add_paragraph("Behavioral Observation Log")
title.runs[0].bold = True
title.runs[0].font.size = Pt(14)

doc.add_paragraph("")

# Add instructions
instructions = doc.add_paragraph()
instructions.add_run("TASK INSTRUCTIONS:\n").bold = True
instructions.add_run(
    "Read the raw family notes in the file 'mom_observations_raw.txt' (located in the same folder). "
    "Transform these scattered observations into a structured medical document suitable for a neurologist appointment.\n\n"
)

instructions.add_run("Required sections:\n").bold = True
instructions.add_run(
    "1. Patient Information Header (name, DOB, observation period, current medications)\n"
    "2. Purpose Statement (why this log was created)\n"
    "3. Incident Log - organize observations by date with:\n"
    "   - Date and time\n"
    "   - Behavior category (Memory, Safety, Mood/Agitation, Orientation, ADL)\n"
    "   - Description\n"
    "   - Observer name\n"
    "4. Pattern Summary - identify patterns such as:\n"
    "   - Frequency by category\n"
    "   - Time of day patterns (sundowning)\n"
    "   - Safety concerns\n"
    "5. Questions for Doctor - specific questions based on observations\n\n"
)

instructions.add_run("Delete these instructions and create the structured document below.\n").italic = True

doc.add_paragraph("")
doc.add_paragraph("=" * 70)
doc.add_paragraph("")

# Add hint about where to start
hint = doc.add_paragraph("BEGIN YOUR STRUCTURED LOG HERE")
hint.runs[0].bold = True

doc.save(sys.argv[1])
print(f"Document template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_dementia_doc.py
python3 /tmp/create_dementia_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document template created at: $DOC_PATH"

# Launch ONLYOFFICE with the document template
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_dementia_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_dementia_task.log || true
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

echo "=== Dementia Observation Log Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  - Raw family notes available at: $RAW_NOTES_PATH"
echo "  - Create structured behavioral log at: $DOC_PATH"
echo ""
echo "Required elements:"
echo "  1. Patient info header (name, DOB, observation period, medications)"
echo "  2. Purpose statement"
echo "  3. Organized incident log (minimum 8 incidents with dates, categories, descriptions)"
echo "  4. Pattern summary (identify at least 2 patterns)"
echo "  5. Questions for neurologist"
echo "  6. Professional formatting suitable for medical appointment"
echo ""
echo "Behavior categories: Memory, Safety, Mood/Agitation, Orientation, ADL"