#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Legal Timeline Assembly Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the timeline draft document with incomplete/messy content
DOC_PATH="$WORKSPACE_DIR/timeline_draft.docx"

cat > /tmp/create_timeline.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Add header
heading = doc.add_paragraph()
heading.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = heading.add_run("PROPERTY DISPUTE DISCOVERY TIMELINE")
run.bold = True
run.font.size = Pt(16)

heading2 = doc.add_paragraph()
heading2.alignment = WD_ALIGN_PARAGRAPH.CENTER
run2 = heading2.add_run("Sarah Mitchell v. Greenwood Properties LLC")
run2.font.size = Pt(12)

doc.add_paragraph()

# Add instruction section (TO BE REMOVED by agent)
instruction = doc.add_paragraph()
run_inst = instruction.add_run("INSTRUCTIONS FOR COMPLETION:")
run_inst.bold = True
run_inst.font.color.rgb = RGBColor(255, 0, 0)

doc.add_paragraph("• Remove this instruction section before final submission")
doc.add_paragraph("• Integrate all events from additional_events.txt file")
doc.add_paragraph("• Ensure all entries are chronologically ordered")
doc.add_paragraph("• Complete any entries marked as [INCOMPLETE] or [TBD]")
doc.add_paragraph("• Ensure consistent formatting (all dates should be bold)")
doc.add_paragraph()

# Add timeline table
table = doc.add_table(rows=1, cols=3)
table.style = 'Light Grid Accent 1'

# Header row
header_cells = table.rows[0].cells
header_cells[0].text = "Date"
header_cells[1].text = "Event Description"
header_cells[2].text = "Exhibit Reference"

# Make header bold
for cell in header_cells:
    for paragraph in cell.paragraphs:
        for run in paragraph.runs:
            run.bold = True

# Add some existing events (some complete, some incomplete, some with formatting issues)

# Event 1: Complete and properly formatted
row = table.add_row().cells
run1 = row[0].paragraphs[0].add_run("06/15/2024")
run1.bold = True
row[1].text = "Signed lease agreement and completed move-in inspection"
row[2].text = "Exhibit A"

# Event 2: Incomplete - missing exhibit reference
row = table.add_row().cells
run2 = row[0].paragraphs[0].add_run("07/01/2024")
run2.bold = True
row[1].text = "Paid first month's rent and security deposit ($2,400)"
row[2].text = "[TBD - Add exhibit reference]"

# Event 3: Formatting issue - date not bold
row = table.add_row().cells
row[0].text = "07/12/2024"  # NOT BOLD - needs fixing
row[1].text = "Reported leaking kitchen faucet to landlord via email"
row[2].text = "Exhibit C"

# Event 4: Incomplete - missing description details
row = table.add_row().cells
run4 = row[0].paragraphs[0].add_run("08/10/2024")
run4.bold = True
row[1].text = "[INCOMPLETE - Add details about inspection]"
row[2].text = "Exhibit D"

# Event 5: Complete
row = table.add_row().cells
run5 = row[0].paragraphs[0].add_run("09/01/2024")
run5.bold = True
row[1].text = "Paid September rent on time via bank transfer"
row[2].text = "Exhibit E"

# Event 6: Formatting issue and incomplete
row = table.add_row().cells
row[0].text = "09/20/2024"  # NOT BOLD
row[1].text = "Landlord entered apartment without notice"
row[2].text = "[TBD]"

# Event 7: Complete
row = table.add_row().cells
run7 = row[0].paragraphs[0].add_run("10/15/2024")
run7.bold = True
row[1].text = "Received notice of intent to withhold security deposit"
row[2].text = "Exhibit F"

# Note: Additional events from notes file need to be inserted between these dates

doc.save(sys.argv[1])
print(f"Timeline draft created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_timeline.py
python3 /tmp/create_timeline.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Timeline draft created at: $DOC_PATH"

# Create additional events notes file on Desktop
NOTES_PATH="/home/ga/Desktop/additional_events.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
ADDITIONAL EVENTS TO INTEGRATE INTO TIMELINE
=============================================

These events occurred during the tenancy but were not included in the draft timeline.
Please add them to the timeline in chronological order.

EVENT 1:
Date: July 3, 2024
Description: First water leak reported - ceiling leak in bedroom during rainstorm, called landlord emergency line
Exhibit: Exhibit B

EVENT 2:
Date: July 20, 2024
Description: Second ceiling leak occurred, discovered visible mold growth on bedroom ceiling, sent photos to landlord
Exhibit: Exhibit B-1

EVENT 3:
Date: August 5, 2024
Description: Sent formal written complaint via certified mail requesting immediate mold remediation and roof repair
Exhibit: Exhibit C-1

EVENT 4:
Date: August 30, 2024
Description: Landlord responded via email stating repairs would be scheduled within 30 days
Exhibit: Exhibit D-1

EVENT 5:
Date: September 15, 2024
Description: Hired independent mold inspector due to health concerns, inspection revealed toxic black mold (Stachybotrys)
Exhibit: Exhibit E-1

NOTES FOR INCOMPLETE ENTRIES:
- August 10, 2024 event: This was the landlord's first property inspection after mold complaint. Description should be: "Landlord conducted property inspection, claimed mold was due to tenant negligence (disputed)"
- September 20, 2024 exhibit should be: Exhibit E-2

FORMATTING REMINDER:
- All dates in the Date column should be bolded
- All exhibit references should follow format "Exhibit X" or "Exhibit X-1"
- Ensure chronological order from earliest to latest date
NOTESEOF

chown ga:ga "$NOTES_PATH"

echo "✅ Additional events notes created at: $NOTES_PATH"

# Launch ONLYOFFICE with the timeline document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_timeline_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_timeline_task.log || true
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

echo "=== Legal Timeline Assembly Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You are finalizing a legal discovery timeline for a property dispute."
echo "  The timeline draft has several issues that need correction:"
echo ""
echo "📝 TASKS TO COMPLETE:"
echo "  1. Remove the red INSTRUCTIONS section at the top"
echo "  2. Review additional_events.txt on Desktop for events to add"
echo "  3. Insert 5 new events from notes into timeline table (chronological order)"
echo "  4. Complete the incomplete entry for August 10, 2024"
echo "  5. Add missing exhibit references (September 20 = Exhibit E-2)"
echo "  6. Fix formatting: ensure ALL dates are bold"
echo "  7. Verify chronological order (earliest to latest)"
echo "  8. Save document (Ctrl+S)"
echo ""
echo "⏰ Discovery deadline is in 48 hours - document must be submission-ready!"