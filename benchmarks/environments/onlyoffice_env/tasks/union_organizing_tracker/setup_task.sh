#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Union Organizing Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with basic structure
DOC_PATH="$WORKSPACE_DIR/workplace_tracker.docx"

cat > /tmp/create_tracker_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Add instructional paragraph
intro = doc.add_paragraph()
intro.add_run('TASK: Create a workplace organizing documentation tracker.\n\n').bold = True
intro.add_run('Your goal is to create a comprehensive document for tracking workplace issues and organizing efforts. ')
intro.add_run('Follow the structure below and fill in realistic content.\n\n')

# Structure guidelines
doc.add_heading('Required Document Structure:', level=2)

doc.add_paragraph('1. Document Header:', style='List Number')
doc.add_paragraph('   - Title: "Workplace Safety and Fairness Initiative"')
doc.add_paragraph('   - Subtitle: "Documentation and Action Plan"')
doc.add_paragraph('   - Current date')
doc.add_paragraph('   - Confidentiality note: "CONFIDENTIAL - For organizing purposes only"')
doc.add_paragraph()

doc.add_paragraph('2. Section 1 - Documented Issues (TABLE):', style='List Number')
doc.add_paragraph('   - Create table with 5 columns: Date | Category | Description | Impact | Evidence')
doc.add_paragraph('   - Add at least 6 incident rows')
doc.add_paragraph('   - Categories should include: Safety, Wage Theft, Break Policy, Retaliation, Other')
doc.add_paragraph('   - Example incidents: heat exhaustion cases, missing overtime pay, bathroom break limits, etc.')
doc.add_paragraph()

doc.add_paragraph('3. Section 2 - Know Your Rights (BULLETS):', style='List Number')
doc.add_paragraph('   - At least 4 bullet points about labor rights')
doc.add_paragraph('   - Must mention: NLRA or Section 7 or union organizing rights')
doc.add_paragraph('   - Include NLRB contact information')
doc.add_paragraph()

doc.add_paragraph('4. Section 3 - Interest Tracker (TABLE):', style='List Number')
doc.add_paragraph('   - Create table with 3 columns: Department/Shift | Interest Level | Notes')
doc.add_paragraph('   - Add at least 8 rows for different departments/shifts')
doc.add_paragraph('   - Interest levels: Strong Support, Interested, Undecided, Opposed, Unknown')
doc.add_paragraph('   - Use department/shift names, NOT individual worker names (for security)')
doc.add_paragraph()

doc.add_paragraph('5. Section 4 - Next Steps (NUMBERED LIST):', style='List Number')
doc.add_paragraph('   - At least 5 concrete action items')
doc.add_paragraph('   - At least 3 must include target dates or timeframes')
doc.add_paragraph('   - Examples: Contact union organizer, hold meeting, gather documentation, etc.')
doc.add_paragraph()

doc.add_paragraph()
doc.add_paragraph('=' * 60)
doc.add_paragraph()
doc.add_heading('BEGIN YOUR DOCUMENT BELOW THIS LINE', level=2)
doc.add_paragraph()
doc.add_paragraph('[Delete these instructions and create your document here]')

doc.save(sys.argv[1])
print(f"Document template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_tracker_doc.py
python3 /tmp/create_tracker_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document template created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_union_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_union_task.log || true
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

echo "=== Union Organizing Tracker Task Setup Complete ==="
echo ""
echo "📋 TASK SUMMARY:"
echo "Create a workplace organizing documentation tracker with the following sections:"
echo ""
echo "SECTION 1: DOCUMENT HEADER"
echo "  • Title: 'Workplace Safety and Fairness Initiative'"
echo "  • Subtitle: 'Documentation and Action Plan'"
echo "  • Date: [current date]"
echo "  • Confidentiality note"
echo ""
echo "SECTION 2: DOCUMENTED ISSUES (Table)"
echo "  • 5 columns: Date, Category, Description, Impact, Evidence"
echo "  • At least 6 incidents (heat exhaustion, wage theft, break policy, etc.)"
echo "  • Categories: Safety, Wage Theft, Break Policy, Retaliation, Other"
echo ""
echo "SECTION 3: KNOW YOUR RIGHTS (Bullets)"
echo "  • 4+ bullet points about labor law"
echo "  • Mention NLRA/Section 7 rights"
echo "  • Include NLRB contact info"
echo ""
echo "SECTION 4: INTEREST TRACKER (Table)"
echo "  • 3 columns: Department/Shift, Interest Level, Notes"
echo "  • 8+ rows with different departments"
echo "  • Use departments, NOT individual names"
echo "  • Interest levels: Strong Support, Interested, Undecided, Opposed, Unknown"
echo ""
echo "SECTION 5: NEXT STEPS (Numbered list)"
echo "  • 5+ concrete action items"
echo "  • Include target dates for at least 3 items"
echo "  • Examples: contact organizer, hold meeting, gather docs, research unions"
echo ""
echo "💾 SAVE: Press Ctrl+S when complete"
echo ""