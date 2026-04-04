#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Study Group Coordination Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the reference information file
INFO_PATH="$WORKSPACE_DIR/study_info.txt"

cat > "$INFO_PATH" << 'INFOEOF'
Study Group Members:
- Alex Chen (you) - available evenings
- Jordan Martinez - works weekends, free Mon/Wed/Fri
- Sam Patel - athlete, free Tue/Thu afternoons
- Casey O'Brien - night shift worker, prefers mornings
- Morgan Lee - commuter, available after 6pm

Exam Topics to Cover:
1. Cell structure and organelles
2. Photosynthesis and cellular respiration
3. DNA replication and protein synthesis
4. Mitosis and meiosis
5. Mendelian genetics
6. Evolution and natural selection
7. Ecology and ecosystems
8. Human body systems

Proposed Meeting Times:
- Session 1: Tuesday, May 2nd, 4:00 PM - Library Room 204
  Topics to review: Cell structure, DNA basics
- Session 2: Thursday, May 4th, 3:30 PM - Student Center
  Topics to review: Genetics, Evolution
- Session 3: Monday, May 8th, 6:00 PM - Library Room 204
  Topics to review: Ecology, Body systems, Final review

Suggested Topic Distribution:
- Alex and Jordan: Cell structure, Photosynthesis, Respiration
- Sam and Casey: DNA, Mitosis, Meiosis
- Morgan and Alex: Genetics, Evolution
- Everyone: Ecology and Body systems (group work)
INFOEOF

chown ga:ga "$INFO_PATH"

echo "✅ Reference information created at: $INFO_PATH"

# Create a blank document for the task
DOC_PATH="$WORKSPACE_DIR/study_group_plan.docx"

cat > /tmp/create_blank_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

# Create a blank document (not completely empty, just minimal structure)
doc = Document()

# Add a single empty paragraph to ensure the document is valid
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Blank document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_doc.py
python3 /tmp/create_blank_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank document created at: $DOC_PATH"

# Launch ONLYOFFICE with the blank document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_study_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_study_task.log || true
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

# Give the window additional time to fully load
sleep 2

echo "=== Study Group Coordination Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "You are coordinating a study group for a Biology final exam."
echo "Reference information is available at: $INFO_PATH"
echo ""
echo "Create a comprehensive study coordination document with:"
echo ""
echo "1. DOCUMENT TITLE (centered, bold, large font)"
echo "   - Should mention 'Study Group' or 'Biology' or 'Coordination'"
echo ""
echo "2. MEETING SCHEDULE SECTION"
echo "   - Section heading: 'Study Session Schedule' (bold, 14pt)"
echo "   - List 3 study sessions with:"
echo "     • Date and time (e.g., Tuesday, May 2nd, 4:00 PM)"
echo "     • Location (e.g., Library Room 204)"
echo "     • Topics to review for that session"
echo ""
echo "3. MEMBER INFORMATION TABLE"
echo "   - Section heading: 'Group Members' (bold, 14pt)"
echo "   - Create a table with 2-3 columns"
echo "   - Include all 5 members with their availability:"
echo "     • Alex Chen - available evenings"
echo "     • Jordan Martinez - free Mon/Wed/Fri"
echo "     • Sam Patel - free Tue/Thu afternoons"
echo "     • Casey O'Brien - prefers mornings"
echo "     • Morgan Lee - available after 6pm"
echo ""
echo "4. TOPIC ASSIGNMENTS SECTION"
echo "   - Section heading: 'Topic Assignments' (bold, 14pt)"
echo "   - Clearly assign exam topics to members"
echo "   - Show who is responsible for which topics"
echo ""
echo "5. EXAM TOPICS CHECKLIST"
echo "   - Section heading: 'Topics to Cover for Exam' (bold, 14pt)"
echo "   - Formatted bullet or numbered list with at least 6 topics:"
echo "     • Cell structure and organelles"
echo "     • Photosynthesis and cellular respiration"
echo "     • DNA replication and protein synthesis"
echo "     • Mitosis and meiosis"
echo "     • Mendelian genetics"
echo "     • Evolution and natural selection"
echo "     (and others from the reference file)"
echo ""
echo "6. SAVE THE DOCUMENT (Ctrl+S)"
echo ""
echo "════════════════════════════════════════════════════════════════"