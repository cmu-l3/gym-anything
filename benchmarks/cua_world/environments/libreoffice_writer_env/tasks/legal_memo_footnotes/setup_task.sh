#!/bin/bash
set -e
echo "=== Setting up Legal Memo Footnotes task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up previous runs
rm -f /home/ga/Documents/legal_memo_formatted.docx 2>/dev/null || true

# Generate the source document using python-docx
# We embed the python script here to ensure the source doc is always created fresh with specific errors
echo "Generating source legal memorandum..."
cat << 'PYEOF' | python3
import os
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_legal_memo():
    doc = Document()

    # Set intentionally WRONG margins (0.75 inches instead of 1.0)
    for section in doc.sections:
        section.top_margin = Inches(0.75)
        section.bottom_margin = Inches(0.75)
        section.left_margin = Inches(0.75)
        section.right_margin = Inches(0.75)

    # Helper to add a paragraph with wrong formatting
    def add_para(text, bold=False, alignment=WD_ALIGN_PARAGRAPH.LEFT):
        para = doc.add_paragraph()
        para.alignment = alignment
        # Single spacing (wrong - should be double)
        para.paragraph_format.line_spacing = 1.0
        para.paragraph_format.space_after = Pt(0)
        para.paragraph_format.space_before = Pt(0)
        run = para.add_run(text)
        run.font.name = 'Calibri'  # Wrong font - should be serif
        run.font.size = Pt(10)     # Wrong size - should be 12pt
        run.bold = bold
        return para

    # Title - intentionally left-aligned and NOT bold
    add_para("MEMORANDUM OF LAW", bold=False, alignment=WD_ALIGN_PARAGRAPH.LEFT)
    add_para("")

    # Header info
    add_para("RE: Damages for Breach of Construction Contract — Westfield Development Corp. v. Pinnacle Builders, Inc.")
    add_para("Client: Westfield Development Corp.")
    add_para("Date: November 15, 2024")
    add_para("")

    # Section I
    add_para("I. INTRODUCTION", bold=True)
    add_para(
        "This memorandum analyzes the available damages remedies for our client, "
        "Westfield Development Corp., arising from the breach of a construction contract "
        "by Pinnacle Builders, Inc. The contractor abandoned the renovation project at "
        "60% completion. This memorandum examines the applicable legal standards."
    )
    add_para("")

    # Section III (Condensed for task brevity while retaining all citations)
    add_para("III. LEGAL ANALYSIS", bold=True)
    add_para(
        "The foundational principle governing contract damages was established over 170 years ago. "
        "The expectation interest requires that damages place the non-breaching party in the "
        "position it would have occupied had the contract been fully performed. "
        "[See Hadley v. Baxendale, 9 Ex. 341, 156 Eng. Rep. 145 (Court of Exchequer 1854)]"
    )
    add_para(
        "Where a contractor's performance is defective, courts must determine the appropriate measure. "
        "The two principal measures are the cost of completion and the diminution in market value. "
        "[See Jacob & Youngs, Inc. v. Kent, 230 N.Y. 239, 129 N.E. 889 (1921) (Cardozo, J.)]"
    )
    add_para("")
    add_para(
        "The Minnesota Supreme Court adopted an expansive view of the cost-of-completion remedy, "
        "awarding the full cost of performance even though the property value increase was minimal. "
        "[See Groves v. John Wunder Co., 205 Minn. 163, 286 N.W. 235 (1939)]"
    )
    add_para(
        "However, the Oklahoma Supreme Court reached the opposite conclusion in a mining lease case, "
        "limiting recovery to the diminution in market value rather than the cost of restoration. "
        "[See Peevyhouse v. Garland Coal & Mining Co., 382 P.2d 109 (Okla. 1962)]"
    )
    add_para("")
    add_para(
        "In medical contexts, the Massachusetts Supreme Judicial Court allowed recovery for "
        "worsening of condition and pain and suffering from corrective procedures. "
        "[See Sullivan v. O'Connor, 363 Mass. 579, 296 N.E.2d 183 (1973)]"
    )
    add_para(
        "Similarly, the New Hampshire Supreme Court awarded damages representing the difference "
        "between the value of the promised outcome and the actual result delivered in the famous 'hairy hand' case. "
        "[See Hawkins v. McGee, 84 N.H. 114, 146 A. 641 (1929)]"
    )

    # Save
    output_path = "/home/ga/Documents/legal_memo_draft.docx"
    doc.save(output_path)
    os.chown(output_path, 1000, 1000)
    print(f"Created {output_path}")

create_legal_memo()
PYEOF

# Ensure source file exists
if [ ! -f /home/ga/Documents/legal_memo_draft.docx ]; then
    echo "ERROR: Source document generation failed"
    exit 1
fi

# Launch LibreOffice Writer with the document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/legal_memo_draft.docx &"

# Wait for Writer window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "LibreOffice Writer"; then
        echo "Writer window found after ${i}s"
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "LibreOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreOffice Writer" 2>/dev/null || true

# Dismiss any startup dialogs (like "Tip of the Day")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="