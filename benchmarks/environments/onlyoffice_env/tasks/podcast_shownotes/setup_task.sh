#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Podcast Show Notes Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the rough notes document
ROUGH_NOTES_PATH="$WORKSPACE_DIR/history_podcast_rough_notes.docx"

cat > /tmp/create_rough_notes.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Add messy, unformatted interview notes (realistic podcast producer notes)
doc.add_paragraph("history podcast interview with dr patricia hammond about urban renewal")
doc.add_paragraph("")
doc.add_paragraph("episode 12 - urban renewal in riverside - conversation with dr patricia hammond")
doc.add_paragraph("")
doc.add_paragraph("talking about 1960s renewal program at 03:45")
doc.add_paragraph("she mentioned displacement around 12:30")
doc.add_paragraph("highway stuff at 28:15")
doc.add_paragraph("preservation at 36:00")
doc.add_paragraph("")
doc.add_paragraph("topics covered: urban renewal initiative, displacement of riverside community, highway construction and division, modern preservation efforts, lessons for current city planning")
doc.add_paragraph("")
doc.add_paragraph("Dr Hammond background - historian, specializes in 20th century urban development, director of riverside historical society, wrote three books on post-war city planning")
doc.add_paragraph("")
doc.add_paragraph('really good quote from her: "The highway didn\'t just divide the neighborhood physically—it shattered a community that had existed for generations."')
doc.add_paragraph("")
doc.add_paragraph("another quote: \"Urban renewal was sold as progress, but for many families it meant losing everything they had built.\"")
doc.add_paragraph("")
doc.add_paragraph("resources she mentioned:")
doc.add_paragraph("- riverside historical society archives")
doc.add_paragraph("- the death and life of great american cities by jane jacobs")
doc.add_paragraph("- city planning commission meeting minutes from 1965-1970")
doc.add_paragraph("")
doc.add_paragraph("NEED TO FORMAT THIS INTO PROPER SHOW NOTES FOR PODCAST WEBSITE")

doc.save(sys.argv[1])
print(f"Rough notes document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_rough_notes.py
python3 /tmp/create_rough_notes.py "$ROUGH_NOTES_PATH"
chown ga:ga "$ROUGH_NOTES_PATH"

echo "✅ Rough notes document created at: $ROUGH_NOTES_PATH"

# Launch ONLYOFFICE with the rough notes document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$ROUGH_NOTES_PATH' > /tmp/onlyoffice_shownotes_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_shownotes_task.log || true
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

echo "=== Podcast Show Notes Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "Transform the rough notes into professional show notes with:"
echo ""
echo "1. Episode Title (Heading 1):"
echo "   'Episode 12: Urban Renewal in Riverside - A Conversation with Dr. Patricia Hammond'"
echo ""
echo "2. About the Guest (Heading 2):"
echo "   Bio paragraph with Dr. Hammond's credentials"
echo ""
echo "3. Topics Discussed (Heading 2):"
echo "   Bullet list of topics covered"
echo ""
echo "4. Key Moments (Heading 2):"
echo "   Timestamps in BOLD [MM:SS] format with descriptions:"
echo "   [03:45] - Introduction to urban renewal program"
echo "   [12:30] - Personal stories of displacement"
echo "   [28:15] - Highway construction impact"
echo "   [36:00] - Current preservation efforts"
echo ""
echo "5. Notable Quotes (Heading 2):"
echo "   Key quotes from the interview"
echo ""
echo "6. Resources Mentioned (Heading 2):"
echo "   Bullet list of resources"
echo ""
echo "7. Save as: episode_12_shownotes.docx"