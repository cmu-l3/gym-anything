#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Community Grant Proposal Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the grant notes file
NOTES_PATH="$WORKSPACE_DIR/grant_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
PROJECT IDEA: Community Tool Library

PROBLEM: 
- Many residents in Oak Street neighborhood can't afford tools for home repairs
- People buy tools for one-time use, which is a waste of money and space
- Senior citizens especially struggle with home maintenance costs
- Apartments have no storage for tools
- Current situation: people either skip repairs or overpay contractors for simple jobs

SOLUTION:
- Create a lending library of common tools at the community center
- Located in community center basement (space already donated by the center)
- Volunteers will manage checkout system using simple software
- 2-week loan period with renewal option
- Tool maintenance workshops twice a month
- Partner with local hardware store for tool donations

EXPECTED IMPACT:
- Serve 200+ households in first year
- Average savings of $400 per household
- Build community connections through workshops
- Reduce landfill waste from disposable tools

BUDGET IDEAS:
- Initial tool purchase: around $3,000 (drills, saws, ladders, sanders, wrenches, etc.)
- Storage shelving and organization: $800
- Checkout software subscription: $200 first year
- Volunteer training and orientation: $300
- Signage, marketing, and printed materials: $400
- Liability insurance first year: $300

Total should be around $5,000 (matches grant amount)

TIMELINE:
- Month 1: Purchase tools and shelving, set up space
- Month 2: Volunteer training, soft launch
- Month 3: Grand opening, community workshops begin
NOTESEOF

chown ga:ga "$NOTES_PATH"
echo "✅ Grant notes created at: $NOTES_PATH"

# Create a blank proposal document
DOC_PATH="$WORKSPACE_DIR/CommunityGrant_Proposal.docx"

cat > /tmp/create_grant_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

# Create a blank document with minimal content
doc = Document()

# Add a simple instruction paragraph
doc.add_paragraph("Grant Proposal Document")
doc.add_paragraph("")
doc.add_paragraph("Please create your grant proposal here following the required structure.")
doc.add_paragraph("")
doc.add_paragraph("Refer to grant_notes.txt for project information.")

doc.save(sys.argv[1])
print(f"Blank proposal document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_grant_doc.py
python3 /tmp/create_grant_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank proposal document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_grant_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_grant_task.log || true
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

echo "=== Community Grant Proposal Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Create a grant proposal document with the following:"
echo ""
echo "1. PROJECT TITLE:"
echo "   - Include 'Community Tool Library Initiative' prominently"
echo ""
echo "2. SECTION STRUCTURE (use Heading 1 style):"
echo "   - Executive Summary"
echo "   - Problem Statement"
echo "   - Proposed Solution"
echo "   - Budget Justification"
echo ""
echo "3. BUDGET TABLE (in Budget Justification section):"
echo "   - Create a table with 3 columns: Item, Description, Cost"
echo "   - Add at least 4 budget line items"
echo "   - Add a final row showing 'TOTAL PROJECT COST'"
echo ""
echo "4. SAVE the document (Ctrl+S)"
echo ""
echo "📄 Reference notes available at: $NOTES_PATH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"