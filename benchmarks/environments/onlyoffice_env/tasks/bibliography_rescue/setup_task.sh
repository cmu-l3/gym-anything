#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bibliography Rescue Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with messy citations
DOC_PATH="$WORKSPACE_DIR/thesis_references.docx"

cat > /tmp/create_bibliography.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Add title
title = doc.add_paragraph("References")
title.runs[0].bold = True
title.runs[0].font.size = Pt(14)

doc.add_paragraph("")

# Citation 1: MLA-style with full first names, missing DOI, no italics
citation1 = doc.add_paragraph(
    'Thompson, Sarah and James Martin. "The Impact of Climate Change on Arctic Wildlife." '
    'Nature Climate Review 2022, vol. 15, pp. 234-250.'
)

doc.add_paragraph("")

# Citation 2: Book with title first, wrong author format, no italics
citation2 = doc.add_paragraph(
    'Understanding Machine Learning: Theory to Algorithms by Shalev-Shwartz, Shai and '
    'Ben-David, Shai. Cambridge University Press, 2014.'
)

doc.add_paragraph("")

# Citation 3: Website with MLA "Accessed from" language
citation3 = doc.add_paragraph(
    'Chen, Wei. "New Approaches to Natural Language Processing." Accessed from '
    'https://www.example-ai-blog.com/nlp-approaches on March 15, 2023.'
)

doc.add_paragraph("")

# Citation 4: Correct APA structure but Title Case in article title, no italics, missing DOI
citation4 = doc.add_paragraph(
    'Rodriguez, M. A., & Kim, S. Y. (2021). The Role Of Attention Mechanisms In Deep Learning. '
    'Journal of Artificial Intelligence Research, 58, 112-145.'
)

doc.add_paragraph("")

# Citation 5: Book chapter with wrong editor format, no italics
citation5 = doc.add_paragraph(
    'Anderson, Patricia K. "Chapter 3: Economic Models of Sustainability." In Green Economics '
    'for the 21st Century, edited by Robert Hughes and Linda Martinez, pp. 67-89. '
    'Oxford University Press, 2020.'
)

doc.add_paragraph("")

# Citation 6: Edited book with title first
citation6 = doc.add_paragraph(
    'The future of renewable energy / edited by David Foster, Emily Watson, and Michael Torres. '
    'MIT Press 2023.'
)

doc.add_paragraph("")

# Citation 7: Online newspaper with old "Retrieved from" style
citation7 = doc.add_paragraph(
    'Williams, J. R. (2019, September 12). The Hidden Cost of Fast Fashion. The Guardian Online. '
    'Retrieved from https://www.theguardian.com/fashion/hidden-costs'
)

doc.add_paragraph("")

# Citation 8: Conference paper with slightly wrong format
citation8 = doc.add_paragraph(
    "Zhang, L., Patel, R., & O'Brien, K. (2023, June). Quantum computing applications in drug "
    'discovery. Paper presented at the International Conference on Computational Biology, Boston, MA.'
)

doc.add_paragraph("")
doc.add_paragraph("---")
doc.add_paragraph("")

# Add missing information section
info_header = doc.add_paragraph("MISSING INFORMATION TO ADD:")
info_header.runs[0].bold = True

doc.add_paragraph("- Thompson & Martin article DOI: 10.1038/s41558-022-01234-5")
doc.add_paragraph("- Rodriguez & Kim article DOI: 10.1613/jair.1.12456")
doc.add_paragraph("")
doc.add_paragraph(
    "TASK: Convert all citations to proper APA 7th edition format. Fix author names, "
    "article title capitalization (sentence case), add italics to journals and books, "
    "add DOIs, fix punctuation, sort alphabetically, and apply 0.5\" hanging indents."
)

doc.save(sys.argv[1])
print(f"Document with messy citations created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_bibliography.py
python3 /tmp/create_bibliography.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_bibliography_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_bibliography_task.log || true
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

echo "=== Bibliography Rescue Task Setup Complete ==="
echo "📝 Scenario: Graduate thesis due tomorrow - citations are a mess!"
echo ""
echo "Current problems with the 8 citations:"
echo "  - Mixed formats (MLA, APA, incomplete)"
echo "  - Wrong author name formats"
echo "  - Article titles in Title Case (should be sentence case)"
echo "  - Missing italics on journals and books"
echo "  - Missing DOIs (provided at bottom)"
echo "  - Wrong punctuation"
echo "  - Not alphabetically sorted"
echo "  - No hanging indents"
echo ""
echo "Required: Convert ALL to APA 7th edition format:"
echo "  1. Author names: 'LastName, F. M.' format"
echo "  2. Article titles: Sentence case only"
echo "  3. Journal/book titles: Italicized"
echo "  4. Add DOIs from bottom section"
echo "  5. Fix all punctuation"
echo "  6. Sort alphabetically by first author"
echo "  7. Apply 0.5\" hanging indents"
echo "  8. Save (Ctrl+S)"