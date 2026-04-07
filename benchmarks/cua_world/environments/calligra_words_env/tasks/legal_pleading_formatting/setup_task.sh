#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Legal Pleading Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

kill_calligra_processes

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

rm -f /home/ga/Documents/martinez_msj.odt
rm -f /home/ga/Desktop/ca_court_formatting_guide.txt

# ------------------------------------------------------------------
# Create the California Court Formatting Guide on the Desktop
# ------------------------------------------------------------------
cat > /home/ga/Desktop/ca_court_formatting_guide.txt << 'EOF'
California Superior Court Pleading Formatting Guide:

1. Court Caption:
   - The court name (e.g., "Superior Court of the State of California...") must be bold and at least 14pt font.
   - The court name and caption area should be center-aligned.
   - The caption should preferably be formatted as a table for proper alignment of parties and case numbers, but basic text alignment is acceptable.

2. Heading Hierarchy:
   - Main sections (Introduction, Statement of Undisputed Material Facts, Legal Standard, Argument, Conclusion, Declaration of Service) must use Heading 1 style.
   - Subsections under Argument must use Heading 2 style.

3. Body Text Formatting:
   - All body text must be double-spaced (set line height to at least 180% or 200%).
   - Font must be a standard serif typeface (e.g., Times New Roman, Liberation Serif, DejaVu Serif) and at least 11pt (12pt preferred).
   - Paragraph alignment must be justified.

4. Facts Table:
   - The Statement of Undisputed Material Facts must be formatted as a table, not just a plain text list.
EOF
chown ga:ga /home/ga/Desktop/ca_court_formatting_guide.txt

# ------------------------------------------------------------------
# Create the unformatted legal pleading using odfpy
# ALL content is plain P elements — no heading styles, no bold, etc.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Court Caption ──
add_paragraph("Superior Court of the State of California")
add_paragraph("County of Los Angeles")
add_paragraph("Maria Martinez, Plaintiff,")
add_paragraph("v.")
add_paragraph("Pacific Coast Properties, LLC, Defendant.")
add_paragraph("Case No. 2024-CV-03847")
add_paragraph("Defendant's Motion for Summary Judgment")
add_paragraph("Hearing Date: March 15, 2026")
add_paragraph("Time: 9:00 AM")
add_paragraph("Department: 45")
add_paragraph("Action Filed: January 10, 2024")
add_paragraph("")
add_paragraph("Notice of Motion")
add_paragraph("TO ALL PARTIES AND THEIR ATTORNEYS OF RECORD:")
add_paragraph("PLEASE TAKE NOTICE that on March 15, 2026, Defendant Pacific Coast Properties, LLC will move this Court for an order granting summary judgment against Plaintiff Maria Martinez.")
add_paragraph("")

# ── Introduction ──
add_paragraph("Introduction")
add_paragraph("This is a premises liability action arising from a slip-and-fall incident that occurred on November 5, 2023. Plaintiff cannot establish that Defendant breached any duty of care, nor can she establish causation.")
add_paragraph("")

# ── Statement of Facts ──
add_paragraph("Statement of Undisputed Material Facts")
add_paragraph("1. Plaintiff Maria Martinez entered the premises on November 5, 2023.")
add_paragraph("2. The floor was recently mopped and 'wet floor' signs were placed at all entrances.")
add_paragraph("3. Plaintiff admitted in deposition that she saw the 'wet floor' signs.")
add_paragraph("4. Plaintiff ran across the wet floor to catch an elevator.")
add_paragraph("5. Defendant's janitorial logs confirm standard safety procedures were followed.")
add_paragraph("")

# ── Legal Standard ──
add_paragraph("Legal Standard")
add_paragraph("Summary judgment is proper if all the papers submitted show that there is no triable issue as to any material fact and that the moving party is entitled to a judgment as a matter of law. (Code Civ. Proc. § 437c).")
add_paragraph("The moving party bears the initial burden of production to make a prima facie showing of the nonexistence of any triable issue of material fact. (Aguilar v. Atlantic Richfield Co., 25 Cal.4th 826 (2001); Celotex Corp. v. Catrett, 477 U.S. 317 (1986)).")
add_paragraph("")

# ── Argument ──
add_paragraph("Argument")
add_paragraph("Defendant Owed No Duty of Care")
add_paragraph("Under California law, a landowner owes a duty to exercise reasonable care in the management of their property. (Rowland v. Christian, 69 Cal.2d 108 (1968)). However, there is no duty to warn of an obvious danger.")
add_paragraph("")
add_paragraph("No Breach of Any Duty")
add_paragraph("Defendant acted reasonably by placing multiple warning signs in plain view. Plaintiff's own testimony confirms the signs were visible.")
add_paragraph("")
add_paragraph("Plaintiff's Injuries Were Not Caused by Defendant's Conduct")
add_paragraph("Plaintiff's own negligence in running on a known wet floor was the sole proximate cause of her injuries. (Anderson v. Liberty Lobby, Inc., 477 U.S. 242 (1986)).")
add_paragraph("")
add_paragraph("Plaintiff's Comparative Fault Bars Recovery")
add_paragraph("Even if Defendant breached a duty, Plaintiff's overwhelming comparative fault precludes recovery as a matter of law.")
add_paragraph("")

# ── Conclusion ──
add_paragraph("Conclusion")
add_paragraph("For the foregoing reasons, Defendant respectfully requests that this Court grant its Motion for Summary Judgment in its entirety.")
add_paragraph("")

# ── Signature ──
add_paragraph("Signature Block")
add_paragraph("Dated: February 10, 2026")
add_paragraph("By: John Smith, Esq. (SBN 123456)")
add_paragraph("Attorney for Defendant Pacific Coast Properties, LLC")
add_paragraph("")

# ── Declaration ──
add_paragraph("Declaration of Service")
add_paragraph("I declare under penalty of perjury under the laws of the State of California that I served the foregoing document on all interested parties.")

doc.save("/home/ga/Documents/martinez_msj.odt")
PYEOF

chown ga:ga /home/ga/Documents/martinez_msj.odt

# Launch Calligra Words and open the document
launch_calligra_document "/home/ga/Documents/martinez_msj.odt"
wait_for_window "martinez_msj.odt" 30

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Take initial screenshot showing unformatted state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="