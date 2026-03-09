#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Performance Review Prep Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy draft document with unstructured achievement notes
DOC_PATH="$WORKSPACE_DIR/achievement_notes_2024_DRAFT.docx"

cat > /tmp/create_messy_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add a basic title
title_para = doc.add_paragraph("Achievement Notes - 2024")
title_para.runs[0].font.size = Pt(14)
title_para.runs[0].bold = True

doc.add_paragraph("")

# Add messy, unstructured achievement notes
# Mix of formats, weak language, missing quantification, chronological chaos

doc.add_paragraph("worked on the CRM migration project with the IT team")
doc.add_paragraph("")
doc.add_paragraph("Helped organize the Q2 team offsite, about 45 people attended")
doc.add_paragraph("")
doc.add_paragraph("reduced customer support ticket response time")
doc.add_paragraph("")

# Some inconsistent bullet formatting
bullet_para = doc.add_paragraph("Led dashboard redesign that made metrics easier to understand")
bullet_para.style = 'List Bullet'

doc.add_paragraph("")
doc.add_paragraph("Participated in hiring for 2 new team members in March")
doc.add_paragraph("")
doc.add_paragraph("Implemented new onboarding process - reduced time from 2 weeks to 1 week")
doc.add_paragraph("")
doc.add_paragraph("improved cross-functional communication")
doc.add_paragraph("")
doc.add_paragraph("Launched social media campaign in September, got good engagement")
doc.add_paragraph("")
doc.add_paragraph("Worked with marketing on the product launch in June")
doc.add_paragraph("")
doc.add_paragraph("helped mentor 3 junior team members")
doc.add_paragraph("")
doc.add_paragraph("Fixed bugs in the reporting system")
doc.add_paragraph("")

# Another inconsistent bullet
bullet_para2 = doc.add_paragraph("Organized team building event with 30 attendees")
bullet_para2.style = 'List Bullet'

doc.add_paragraph("")
doc.add_paragraph("Contributed to the sales pitch deck redesign")
doc.add_paragraph("")
doc.add_paragraph("Updated documentation for the API")
doc.add_paragraph("")
doc.add_paragraph("reduced meeting time by implementing new agenda format")
doc.add_paragraph("")
doc.add_paragraph("Completed customer feedback analysis project in Q3")
doc.add_paragraph("")
doc.add_paragraph("worked on improving team collaboration tools")
doc.add_paragraph("")
doc.add_paragraph("Successfully launched new feature that increased user engagement")
doc.add_paragraph("")
doc.add_paragraph("Helped with quarterly business review presentation in December")
doc.add_paragraph("")
doc.add_paragraph("Streamlined reporting process saving team time")
doc.add_paragraph("")
doc.add_paragraph("participated in cross-functional strategy sessions")
doc.add_paragraph("")
doc.add_paragraph("Delivered training sessions on new software tools")
doc.add_paragraph("")
doc.add_paragraph("Reduced project delivery time through better planning")
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Messy achievement document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_messy_doc.py
python3 /tmp/create_messy_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Messy achievement document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_review_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_review_task.log || true
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

echo "=== Performance Review Prep Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "Transform the messy achievement notes into a professional performance review brag sheet."
echo ""
echo "Requirements:"
echo "  1. Create document structure:"
echo "     - Main title as Heading 1: '2024 Performance Review - Achievement Summary'"
echo "     - Section headers as Heading 2 (e.g., 'Q1 2024 Achievements', 'Q2 2024 Achievements')"
echo "     - OR category-based sections (e.g., 'Project Leadership', 'Process Improvements')"
echo ""
echo "  2. Format all achievements as consistent bullet points"
echo ""
echo "  3. Strengthen language:"
echo "     - Replace 'worked on' with 'Led', 'Delivered', 'Completed'"
echo "     - Replace 'helped' with 'Organized', 'Facilitated', 'Coordinated'"
echo "     - Replace 'participated' with 'Contributed', 'Collaborated'"
echo ""
echo "  4. Add quantification and bold all metrics:"
echo "     - Add specific numbers where missing (or use placeholders like [INSERT: %])"
echo "     - Bold all numeric values (percentages, dollar amounts, counts, timeframes)"
echo ""
echo "  5. Organize chronologically or by category"
echo ""
echo "  6. Save as: 'Maya_Thompson_2024_Brag_Sheet.docx'"
echo ""
echo "Example transformation:"
echo "  Before: 'worked on the CRM migration project with the IT team'"
echo "  After:  '• Led CRM migration project across 3 departments, completing **2 weeks ahead** of schedule'"
echo ""