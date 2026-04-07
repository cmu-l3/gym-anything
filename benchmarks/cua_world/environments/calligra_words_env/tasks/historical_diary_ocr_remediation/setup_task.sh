#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Historical Diary OCR Remediation Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

kill_calligra_processes

rm -f /home/ga/Documents/lewis_clark_ocr_raw.odt
rm -f /home/ga/Desktop/ocr_correction_guide.txt

# Create the OCR guide
cat > /home/ga/Desktop/ocr_correction_guide.txt << 'EOF'
OCR CORRECTION GUIDE

Please fix the following recurring character recognition errors in the manuscript:
1. "rn" recognized as "m"
   Examples: "moming" should be "morning", "govemment" should be "government".
2. "in" recognized as "m"
   Example: "agarnst" should be "against".
3. "1" (number one) recognized as "l" (lowercase L) in dates
   Example: "l804" should be "1804".

FORMATTING REQUIREMENTS:
- Remove arbitrary line breaks within paragraphs to create continuous flowing text.
- Rejoin hyphenated words split across lines (e.g., "provi- sions" -> "provisions").
- Format all daily entry dates as Bold and Center aligned.
- Format all body text as Justified alignment with a 0.5" (1.27 cm) first-line indent.
EOF
chown ga:ga /home/ga/Desktop/ocr_correction_guide.txt

# Create the raw ODT with intentional errors
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("JOURNAL OF THE EXPEDITION")
add_paragraph("")
add_paragraph("Monday, May 14, l804")
add_paragraph("Set out at 4 oClock P.M., in the pres-")
add_paragraph("ence of many of the neighboring inhab-")
add_paragraph("itants, and proceeded on under a jentle")
add_paragraph("breese up the Missourie to the upper")
add_paragraph("point of the first island 4 Miles and")
add_paragraph("camped on the island which is Situated")
add_paragraph("Close on the right or Starboard Side,")
add_paragraph("and opposit the mouth of a Small Creek")
add_paragraph("called Cold water, a heavy rain this")
add_paragraph("after-noon.")
add_paragraph("")
add_paragraph("Wednesday, May 16, l804")
add_paragraph("We arrived at St. Charles at 12 oClock")
add_paragraph("a number Spectators french & Indians")
add_paragraph("flocked to the bank to See the party.")
add_paragraph("This Village is about one mile in length,")
add_paragraph("Situated on the North Side of the Missourie")
add_paragraph("at the foot of a hill from which it takes its")
add_paragraph("name Peetiete Coete or the Little hill")
add_paragraph("This Village Contns. about 100 houses,")
add_paragraph("the most of them small and indiferent")
add_paragraph("and about 450 inhabitents Chiefly French,")
add_paragraph("those people appear Much delighted with")
add_paragraph("our exped-")
add_paragraph("ition and the change of govemment.")
add_paragraph("They are a polite & hospitable people.")
add_paragraph("")
add_paragraph("Monday, May 21, l804")
add_paragraph("Set out at half passed three oClock under")
add_paragraph("three Cheers from the gentlemen on the")
add_paragraph("bank and proceeded on to the head of the")
add_paragraph("Island which is Situated on the Starboard")
add_paragraph("Side 3 Miles. we met two large Canoes")
add_paragraph("loaded with furs & Pelteries, from the")
add_paragraph("Mahas nation, and another with provi-")
add_paragraph("sions agarnst the current.")
add_paragraph("The moming was fair, and the wind from")
add_paragraph("the East. We camped at the head of the")
add_paragraph("island.")
add_paragraph("")
add_paragraph("UNIQUE_WATERMARK_STR_9942")

doc.save("/home/ga/Documents/lewis_clark_ocr_raw.odt")
PYEOF

chown ga:ga /home/ga/Documents/lewis_clark_ocr_raw.odt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/lewis_clark_ocr_raw.odt"
wait_for_window "lewis_clark_ocr_raw" 30

# Maximize the window
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="