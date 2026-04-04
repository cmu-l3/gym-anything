#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prior Learning Portfolio Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the rough notes document
ROUGH_NOTES_PATH="$WORKSPACE_DIR/PLA_rough_notes.docx"

cat > /tmp/create_rough_notes.py << 'PYEOF'
#!/usr/bin/env python3
"""
Create rough notes document for PLA portfolio task
This simulates messy notes from an advising session
"""
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Messy, unformatted content - no proper structure
doc.add_paragraph("PRIOR LEARNING ASSESSMENT - BUS 210 Small Business Management")
doc.add_paragraph("")
doc.add_paragraph("Student: Maria Gutierrez, ID# 23457890")
doc.add_paragraph("")
doc.add_paragraph("=== NOTES FROM ADVISOR MEETING ===")
doc.add_paragraph("")

# Course objectives (copy-pasted, needs to be reformatted)
doc.add_paragraph("COURSE LEARNING OBJECTIVES (from catalog):")
doc.add_paragraph("Demonstrate understanding of business planning and strategy development")
doc.add_paragraph("Apply financial management principles including budgeting and cost control")
doc.add_paragraph("Analyze market research and customer needs assessment")
doc.add_paragraph("Evaluate vendor relationships and supply chain management")
doc.add_paragraph("Design marketing and promotional strategies for small businesses")
doc.add_paragraph("")

# Experience notes (needs to be narrative form)
doc.add_paragraph("MY WORK EXPERIENCE - wedding planning business")
doc.add_paragraph("- Business name: Elegant Moments")
doc.add_paragraph("- Started in 2008, closed in 2020 (12 years)")
doc.add_paragraph("- Handled 85+ weddings, budgets from $15K to $150K")
doc.add_paragraph("- Did everything: contracts, budgets, vendor coordination, marketing")
doc.add_paragraph("- Had to manage cash flow, negotiate with vendors, handle difficult clients")
doc.add_paragraph("- Created detailed budgets for every wedding, tracked expenses")
doc.add_paragraph("- Built relationships with 30+ vendors (venues, caterers, florists, photographers)")
doc.add_paragraph("- Used social media, website, bridal shows for marketing")
doc.add_paragraph("")

# Advisor's notes about what to include (handwritten notes transcribed)
doc.add_paragraph("ADVISOR NOTES:")
doc.add_paragraph("* Need to MAP each learning objective to specific examples from your work")
doc.add_paragraph("* Create a TABLE with 3 columns - objective, evidence, supporting docs")
doc.add_paragraph("* Write a reflection connecting your experience to business THEORY")
doc.add_paragraph("* Use academic language! Say things like 'applied business principles' not just 'did the work'")
doc.add_paragraph("* Include list of supporting documents you'll submit")
doc.add_paragraph("* MUST follow formatting guidelines or they'll reject without reading!")
doc.add_paragraph("")

# Some content in wrong section
doc.add_paragraph("SUPPORTING DOCUMENTS I HAVE:")
doc.add_paragraph("- Client contracts (samples with names redacted)")
doc.add_paragraph("- Vendor agreements and price lists")
doc.add_paragraph("- Budget spreadsheets from multiple weddings")
doc.add_paragraph("- Marketing materials (website screenshots, social media analytics)")
doc.add_paragraph("- Testimonials from clients")
doc.add_paragraph("")

# Partial reflection (needs expansion)
doc.add_paragraph("WHY THIS MATTERS:")
doc.add_paragraph("My wedding planning business wasn't just coordinating events - it was running a complete small business. I had to do strategic planning, financial management, marketing, and operations. Everything in BUS 210 is what I did in real life. The practical experience I gained over 12 years demonstrates mastery of small business management concepts.")
doc.add_paragraph("")

# Formatting requirements (for reference)
doc.add_paragraph("=== FORMATTING REQUIREMENTS (from PLA guidelines) ===")
doc.add_paragraph("- Cover page: Title (14pt bold centered), course name, student info")
doc.add_paragraph("- All section headings: 14pt bold")
doc.add_paragraph("- Body text: Times New Roman 12pt")
doc.add_paragraph("- Narrative sections: double-spaced, justified")
doc.add_paragraph("- Margins: 1 inch all sides")
doc.add_paragraph("- Page numbers: bottom center (not on cover page)")
doc.add_paragraph("- Header: 'PLA Portfolio - Maria Gutierrez' (top right, not on cover page)")

doc.save(sys.argv[1])
print(f"Rough notes document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_rough_notes.py
python3 /tmp/create_rough_notes.py "$ROUGH_NOTES_PATH"
chown ga:ga "$ROUGH_NOTES_PATH"

echo "✅ Rough notes created at: $ROUGH_NOTES_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$ROUGH_NOTES_PATH' > /tmp/onlyoffice_pla_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_pla_task.log || true
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

echo "=== Prior Learning Portfolio Task Setup Complete ==="
echo ""
echo "📚 SCENARIO:"
echo "Maria Gutierrez is a returning adult student who ran a wedding planning"
echo "business for 12 years. She wants to earn college credit for BUS 210"
echo "(Small Business Management) through Prior Learning Assessment."
echo ""
echo "The rough notes document contains all necessary information but is"
echo "disorganized and improperly formatted. Transform it into a formal"
echo "academic portfolio that meets the university's strict requirements."
echo ""
echo "📝 REQUIRED SECTIONS (in order):"
echo "  1. Cover Page"
echo "     - Title: 'Prior Learning Assessment Portfolio' (14pt bold, centered)"
echo "     - Subtitle: 'BUS 210: Small Business Management' (12pt, centered)"
echo "     - Student: Maria Gutierrez"
echo "     - Student ID: 23457890"
echo "     - Date: (current date)"
echo ""
echo "  2. Course Learning Objectives"
echo "     - Heading: 'Course Learning Objectives' (14pt bold)"
echo "     - 5 objectives as numbered list (1. 2. 3. 4. 5.)"
echo "     - Double-spaced"
echo ""
echo "  3. Relevant Professional Experience"
echo "     - Heading: 'Relevant Professional Experience' (14pt bold)"
echo "     - 2-3 paragraphs narrative form"
echo "     - Must mention: 'Elegant Moments', years 2008-2020, 85+ weddings"
echo "     - Justified alignment, double-spaced"
echo ""
echo "  4. Competency Evidence Matrix"
echo "     - Heading: 'Competency Evidence Matrix' (14pt bold)"
echo "     - Table with 3 columns:"
echo "       * Learning Objective"
echo "       * Evidence from Experience"
echo "       * Supporting Material"
echo "     - 5 rows (one for each objective)"
echo ""
echo "  5. Reflective Analysis"
echo "     - Heading: 'Reflective Analysis' (14pt bold)"
echo "     - 1-2 paragraphs"
echo "     - Must use academic language (e.g., 'applied business theory')"
echo "     - Double-spaced"
echo ""
echo "  6. Appendix: Supporting Documents"
echo "     - Heading: 'Appendix: Supporting Documents' (14pt bold)"
echo "     - Bulleted list of at least 3 items:"
echo "       * Client contracts (samples)"
echo "       * Vendor agreements"
echo "       * Budget spreadsheets"
echo ""
echo "📐 FORMATTING REQUIREMENTS:"
echo "  - Font: Times New Roman, 12pt for body text"
echo "  - Section headings: 14pt bold"
echo "  - Margins: 1 inch on all sides"
echo "  - Line spacing: Double-spaced for narrative sections"
echo "  - Page numbers: Bottom center (start from page 2)"
echo "  - Header: 'PLA Portfolio - Maria Gutierrez' (top right, except cover)"
echo ""
echo "💾 SAVE AS:"
echo "  /home/ga/Documents/TextDocuments/PLA_Portfolio_Final.docx"
echo ""
echo "⚠️  The university will REJECT the portfolio if formatting is incorrect!"
echo "    Maria is counting on this to save $1,200 in tuition."