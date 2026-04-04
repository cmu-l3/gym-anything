#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Noise Complaint Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank document to start
DOC_PATH="$WORKSPACE_DIR/noise_complaint.docx"

cat > /tmp/create_noise_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Start with completely blank document
# Agent will create everything from scratch

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_noise_doc.py
python3 /tmp/create_noise_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_noise_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_noise_task.log || true
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

echo "=== Noise Complaint Log Task Setup Complete ==="
echo ""
echo "📝 TASK: Create a professional noise complaint document"
echo ""
echo "REQUIRED STRUCTURE:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. DOCUMENT HEADER (centered, formatted):"
echo "   Title: 'Noise Disturbance Log - Unit 4B' (bold, 16pt)"
echo "   Your name: 'Alex Martinez' (14pt)"
echo "   Date range: 'January 15 - February 4, 2025'"
echo ""
echo "2. OPENING STATEMENT (2-3 sentences):"
echo "   Professional summary mentioning:"
echo "   - Noise from Unit 5B"
echo "   - Sleep disruption impact"
echo "   - Request for landlord intervention"
echo ""
echo "3. INCIDENT LOG TABLE (with borders):"
echo "   Columns: Date | Time | Duration | Type of Noise | Impact"
echo "   Header row should be BOLD"
echo ""
echo "   DATA TO ENTER (8 incidents):"
echo "   ┌─────────┬──────────┬──────────┬────────────────┬─────────────────────┐"
echo "   │ Jan 15  │ 11:45 PM │ 2 hours  │ Loud music, bass │ Woke me up        │"
echo "   │ Jan 17  │ 1:30 AM  │ 1.5 hours│ Music, stomping  │ Couldn't sleep    │"
echo "   │ Jan 19  │ 12:00 AM │ 3 hours  │ Party, voices    │ Lost 3 hrs sleep  │"
echo "   │ Jan 22  │ 11:30 PM │ 2 hours  │ Music, bass      │ Work tired next day│"
echo "   │ Jan 25  │ 2:00 AM  │ 1 hour   │ Loud voices      │ Woke from sleep   │"
echo "   │ Jan 28  │ 10:30 PM │ 4 hours  │ Party            │ Completely sleepless│"
echo "   │ Feb 1   │ 1:00 AM  │ 2.5 hours│ Music, bass      │ Exhausted at work │"
echo "   │ Feb 4   │ 12:30 AM │ 2 hours  │ Music            │ Missed morning mtg│"
echo "   └─────────┴──────────┴──────────┴────────────────┴─────────────────────┘"
echo ""
echo "4. IMPACT SUMMARY SECTION:"
echo "   Heading: 'Summary of Impact' (bold, 14pt)"
echo ""
echo "   Subsection A - 'Frequency Analysis' (bold, 12pt):"
echo "   - Total incidents in 21-day period: 8"
echo "   - Average: 2.7 incidents per week"
echo "   - Pattern: late-night (10:30 PM - 2:30 AM)"
echo ""
echo "   Subsection B - 'Sleep Impact' (bold, 12pt):"
echo "   - Total sleep disruption: 18 hours over 3 weeks"
echo "   - Average: 6 hours per week of lost sleep"
echo "   - Resulted in workplace performance issues"
echo ""
echo "5. CLOSING REQUEST:"
echo "   Professional paragraph requesting:"
echo "   - Landlord intervention"
echo "   - Discussion with Unit 5B tenant about quiet hours"
echo ""
echo "FORMATTING REQUIREMENTS:"
echo "  • Line spacing: 1.5"
echo "  • Font: 11pt for body text"
echo "  • Margins: 1 inch"
echo "  • Save document: Ctrl+S"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"