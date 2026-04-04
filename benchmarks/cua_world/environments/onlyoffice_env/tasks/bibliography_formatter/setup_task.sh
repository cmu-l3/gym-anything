#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bibliography Formatter Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with messy bibliography
DOC_PATH="$WORKSPACE_DIR/research_sources.docx"

cat > /tmp/create_biblio.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add messy heading (not centered, needs replacement)
heading = doc.add_paragraph("My Sources (NEEDS FORMATTING)")
heading.runs[0].bold = False
heading.runs[0].font.size = Pt(12)

# Add blank line
doc.add_paragraph("")

# Add 10 bibliography entries in RANDOM order (not alphabetical)
# Mix of books, journal articles, reports
# No hanging indent, no italics, inconsistent formatting

entries = [
    'Wilson, Margaret. The Psychology of Climate Denial. Academic Press, 2019.',
    
    '"Solar Energy Adoption in Rural Communities." Energy Policy Journal, vol. 45, no. 3, 2020, pp. 234-249.',
    
    'National Institute of Environmental Studies. Climate Action Report 2021. Government Printing Office, 2021.',
    
    'Thompson, James and Sarah Chen. Renewable Energy Economics. MIT Press, 2018.',
    
    '"The Role of Policy in Carbon Reduction." Environmental Science Today, vol. 12, 2019, pp. 88-95.',
    
    'Anderson, Patricia. Carbon Markets and Trading Systems. Oxford UP, 2020.',
    
    'Global Climate Coalition. Framework for Climate Action. 2020.',
    
    'Roberts, David. "Behavioral Economics and Environmental Policy." Journal of Policy Analysis, vol. 33, no. 2, 2021, pp. 156-178.',
    
    'Chen, Liu and Maria Rodriguez. Sustainable Development Goals. Routledge, 2019.',
    
    '"Wind Power Infrastructure Challenges." Technology Review, vol. 118, 2020, pp. 45-52.'
]

for entry in entries:
    para = doc.add_paragraph(entry)
    # Make sure there's no special formatting initially
    para.paragraph_format.left_indent = None
    para.paragraph_format.first_line_indent = None
    para.alignment = None  # Left-aligned by default
    
    # Ensure no bold/italic
    for run in para.runs:
        run.bold = False
        run.italic = False

doc.save(sys.argv[1])
print(f"Document created with {len(entries)} bibliography entries: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_biblio.py
python3 /tmp/create_biblio.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_biblio_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_biblio_task.log || true
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

echo "=== Bibliography Formatter Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Replace heading with 'Works Cited' (centered)"
echo "  2. Alphabetize all 10 entries by author last name"
echo "  3. Select all entries and apply 0.5-inch hanging indent"
echo "     (Format → Paragraph → Special: Hanging → 0.5\")"
echo "  4. Italicize book/journal titles (not article titles in quotes)"
echo "  5. Save document (Ctrl+S)"
echo ""
echo "Expected alphabetical order (by last name):"
echo "  Anderson, Chen, Global Climate Coalition, National Institute,"
echo "  Roberts, Thompson, Wilson, + 3 articles (by title)"