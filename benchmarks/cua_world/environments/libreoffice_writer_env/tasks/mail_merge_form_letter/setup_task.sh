#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Mail Merge Form Letter Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the CSV data source with patron records
# Using literary character names from public domain works
cat > /home/ga/Documents/patrons.csv << 'CSVEOF'
Name,Address,City,State,BookTitle,DueDate
Eleanor Vance,142 Hill House Lane,Hillsdale,NY,The Haunting of Hill House,2024-03-15
Santiago Nasar,88 Chronicle Drive,Macondo,FL,Chronicle of a Death Foretold,2024-03-18
Clarissa Dalloway,17 Westminster Gardens,London,CT,Mrs Dalloway,2024-03-22
Jay Gatsby,1 West Egg Boulevard,West Egg,NY,The Great Gatsby,2024-03-25
Atticus Finch,281 Maycomb Street,Maycomb,AL,To Kill a Mockingbird,2024-03-28
CSVEOF

chown ga:ga /home/ga/Documents/patrons.csv
chmod 644 /home/ga/Documents/patrons.csv

# Create the letter template using python-docx
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Library letterhead
header = doc.add_paragraph("Greenfield Public Library")
header.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in header.runs:
    run.bold = True
    run.font.size = Pt(16)

subheader = doc.add_paragraph("456 Main Street, Greenfield, MA 01301")
subheader.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in subheader.runs:
    run.font.size = Pt(10)

doc.add_paragraph("")

# Date
doc.add_paragraph("March 1, 2024")
doc.add_paragraph("")

# Recipient address block
doc.add_paragraph("{Name}")
doc.add_paragraph("{Address}")
doc.add_paragraph("{City}, {State}")
doc.add_paragraph("")

# Salutation
doc.add_paragraph("Dear {Name},")
doc.add_paragraph("")

# Body
doc.add_paragraph(
    "We hope this letter finds you well. We are writing to remind you that "
    "the following item you borrowed from Greenfield Public Library is "
    "approaching its due date:"
)
doc.add_paragraph("")

# Book details
book_para = doc.add_paragraph("    Title: {BookTitle}")
doc.add_paragraph("    Due Date: {DueDate}")
doc.add_paragraph("")

doc.add_paragraph(
    "If you would like to renew this item, you may do so online at "
    "library.greenfield.gov, by phone at (413) 555-0192, or in person "
    "at the circulation desk. Please note that items may be renewed up "
    "to two times, provided there are no holds placed by other patrons."
)
doc.add_paragraph("")

doc.add_paragraph(
    "Late fees are assessed at $0.25 per day for books and $1.00 per day "
    "for audiovisual materials. We appreciate your prompt attention to "
    "this matter."
)
doc.add_paragraph("")

# Closing
doc.add_paragraph("Sincerely,")
doc.add_paragraph("")
doc.add_paragraph("Margaret Chen")
doc.add_paragraph("Head Librarian")
doc.add_paragraph("Greenfield Public Library")

doc.save("/home/ga/Documents/letter_template.docx")
print("Created library renewal notice template")
PYEOF

chown ga:ga /home/ga/Documents/letter_template.docx
chmod 666 /home/ga/Documents/letter_template.docx

# Launch LibreOffice Writer with the template
echo "Launching LibreOffice Writer with template..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/letter_template.docx > /tmp/writer_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/writer_task.log
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Writer" 90; then
    wait_for_window "letter_template" 30 || true
fi

# Click on center of screen to select desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Writer window
echo "Focusing Writer window..."
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Dismiss any "What's New" infobar that may appear on first launch
        safe_xdotool ga :1 key Escape
        sleep 0.3
        # Open Styles sidebar
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

echo "=== Mail Merge Form Letter Task Setup Complete ==="
echo "Instructions:"
echo "  1. The template is open with placeholders: {Name}, {Address}, etc."
echo "  2. CSV data source: /home/ga/Documents/patrons.csv (5 patrons)"
echo "  3. Create personalized letters for all 5 patrons"
echo "  4. Separate letters with page breaks"
echo "  5. Save merged output as /home/ga/Documents/merged_letters.docx"
