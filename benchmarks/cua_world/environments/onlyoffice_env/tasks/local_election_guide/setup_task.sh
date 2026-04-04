#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Local Election Guide Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the candidate information text file
INFO_FILE="$WORKSPACE_DIR/candidate_info.txt"

cat > "$INFO_FILE" << 'EOF'
CITY COUNCIL DISTRICT 4 ELECTION

Candidate Research Notes (from various sources)

Sarah Chen - business owner, website says supports affordable housing, wants more transit
Miguel Rodriguez - teacher, debate said opposes development project, pro parks funding  
James Wilson - retired engineer, supports balanced budget, website mentions traffic concerns

Key Issues for District 4:
- Proposed apartment complex at old factory site (200 units)
- Parks budget cut proposal 
- Traffic congestion on Main St
- Small business support programs

Chen on housing: "We need 200 affordable units" (from candidate forum Sept 15)
Rodriguez on parks: "Parks are essential - restore full funding" (debate Sept 20)
Wilson on traffic: "Traffic study needed before any development" (website)
Chen on business: "Reduce permit fees for small businesses" (email response)
Rodriguez on housing: "Concerned about density, need community input first" (town hall)
Wilson on budget: "No new taxes, find efficiencies" (campaign literature)

Additional context:
- District 4 has seen rapid growth in past 5 years
- Current parks budget: $2.5M (proposed cut to $1.8M)
- Main St traffic increased 35% since 2020
- 127 small businesses in district
- Election date: November 5, 2024
- Early voting: October 20-November 1

Source documents reviewed:
- Candidate websites (all three)
- League of Women Voters candidate forum (Sept 15)
- Channel 7 debate (Sept 20)
- Town hall meeting notes (Sept 22)
- Campaign literature received by mail
EOF

chown ga:ga "$INFO_FILE"

echo "✅ Candidate information file created at: $INFO_FILE"

# Create a minimal starter document to begin with
STARTER_DOC="$WORKSPACE_DIR/voter_guide_draft.docx"

cat > /tmp/create_starter.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Add a blank paragraph as placeholder
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Starter document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_starter.py
python3 /tmp/create_starter.py "$STARTER_DOC"
chown ga:ga "$STARTER_DOC"

echo "✅ Starter document created at: $STARTER_DOC"

# Launch ONLYOFFICE with the starter document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$STARTER_DOC' > /tmp/onlyoffice_election_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_election_task.log || true
    # Don't exit - might still start
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - might still appear
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Local Election Guide Task Setup Complete ==="
echo ""
echo "📋 Source Information:"
echo "   - Candidate research notes: $INFO_FILE"
echo ""
echo "📝 Task Instructions:"
echo "   1. Review the candidate information in candidate_info.txt"
echo "   2. Create a voter guide document with:"
echo "      - Title: 'District 4 City Council Candidate Comparison' (or similar)"
echo "      - Make the title bold and/or larger font (14pt+ or Heading 1)"
echo "      - A comparison table with:"
echo "        * 4 columns: Issue | Sarah Chen | Miguel Rodriguez | James Wilson"
echo "        * At least 4 content rows covering:"
echo "          - Housing/Development"
echo "          - Parks Funding"
echo "          - Traffic/Transportation"
echo "          - Small Business/Budget"
echo "        * Header row should be formatted (bold or shaded)"
echo "        * Fill in each candidate's position based on the info file"
echo "      - A footer section after the table with:"
echo "        * Election date or voting information"
echo "        * Note about sources (e.g., 'Based on campaign materials and forums')"
echo "   3. Ensure table has visible borders"
echo "   4. Use 'Save As' to save as: $WORKSPACE_DIR/voter_guide.docx"
echo ""
echo "Expected file: /home/ga/Documents/TextDocuments/voter_guide.docx"