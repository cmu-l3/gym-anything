#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Meteorological Assessment Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/moore_assessment_draft.odt
rm -f /home/ga/Desktop/nws_report_guidelines.txt

# ------------------------------------------------------------------
# Create the unformatted assessment draft using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("Service Assessment: May 20, 2013 Moore, Oklahoma Tornado")
add_paragraph("National Weather Service")
add_paragraph("[DRAFT NOTE: Ensure final review by NWS Headquarters]")
add_paragraph("")

add_paragraph("Executive Summary")
add_paragraph("On the afternoon of May 20, 2013, a devastating EF5 tornado struck Moore, Oklahoma, causing significant destruction and loss of life. This service assessment evaluates the performance of the National Weather Service (NWS) leading up to and during the event.")
add_paragraph("[TODO: Add executive summary statistics here once confirmed]")
add_paragraph("")

add_paragraph("Meteorological Setup")
add_paragraph("Synoptic Environment")
add_paragraph("The synoptic environment on May 20 featured a potent upper-level trough ejecting across the Southern Plains, interacting with a highly unstable airmass.")
add_paragraph("Radar Analysis")
add_paragraph("Radar imagery showed rapid supercell development along a dryline. The storm exhibited a classic hook echo and a strong velocity couplet.")
add_paragraph("[REVIEW: Insert base velocity radar loop here]")
add_paragraph("")

add_paragraph("Warning Timeline")
add_paragraph("The NWS Norman Forecast Office issued a Tornado Warning for Moore with significant lead time. A Tornado Emergency was declared as the violent nature of the tornado became apparent.")
add_paragraph("[DRAFT NOTE: Verify lead time exact minutes with log]")
add_paragraph("")

add_paragraph("Damage Survey")
add_paragraph("Briarwood Elementary")
add_paragraph("The tornado caused complete destruction of Briarwood Elementary School, with EF5 damage indicators noted in the surrounding neighborhoods.")
add_paragraph("Plaza Towers Elementary")
add_paragraph("Direct impact on Plaza Towers Elementary resulted in tragic loss of life and catastrophic structural failure.")
add_paragraph("[TODO: Confirm fatality count with local ME for this section]")
add_paragraph("")

add_paragraph("Significant Damage Locations")
add_paragraph("Location EF Rating Est. Wind (mph) Fatalities")
add_paragraph("Briarwood Elementary EF5 210 0")
add_paragraph("Plaza Towers Elementary EF5 210 7")
add_paragraph("Moore Medical Center EF4 190 0")
add_paragraph("Orr Family Farm EF4 180 0")
add_paragraph("")

add_paragraph("Conclusion")
add_paragraph("The NWS performance during the May 20, 2013 Moore tornado was exceptional, with significant warning lead times that undoubtedly saved many lives despite the tragic outcomes.")
add_paragraph("[REVIEW: Get signature from NWS Director]")

doc.save("/home/ga/Documents/moore_assessment_draft.odt")
PYEOF

# Create guidelines
cat > /home/ga/Desktop/nws_report_guidelines.txt << 'EOF'
NWS Post-Storm Assessment Formatting Guidelines

1. Document Cleanup: Remove all internal collaboration markers (e.g., [DRAFT NOTE: ...], [TODO: ...], [REVIEW: ...]).
2. Title: The main report title must be bold and at least 16pt font.
3. Heading 1: Apply Heading 1 style to the main sections (Executive Summary, Meteorological Setup, Warning Timeline, Damage Survey, Conclusion).
4. Heading 2: Apply Heading 2 style to the subsections (Synoptic Environment, Radar Analysis, Briarwood Elementary, Plaza Towers Elementary).
5. Data Table: Under "Significant Damage Locations", convert the raw text list into a 4-column table. The table should have columns for "Location", "EF Rating", "Est. Wind (mph)", and "Fatalities".
6. Body Text: Justify all standard body paragraphs.
7. Table of Contents: Insert an automated Table of Contents at the beginning of the document.
EOF

chown ga:ga /home/ga/Documents/moore_assessment_draft.odt
chown ga:ga /home/ga/Desktop/nws_report_guidelines.txt

launch_calligra_document "/home/ga/Documents/moore_assessment_draft.odt"
sleep 5

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="