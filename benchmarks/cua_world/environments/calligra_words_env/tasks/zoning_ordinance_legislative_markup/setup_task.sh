#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Zoning Ordinance Legislative Markup Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/draft_adu_ordinance.odt
rm -f /home/ga/Desktop/ordinance_formatting_rules.txt

# ------------------------------------------------------------------
# Create the ordinance formatting rules text file
# ------------------------------------------------------------------
cat << 'EOF' > /home/ga/Desktop/ordinance_formatting_rules.txt
CITY OF OAKRIDGE - ORDINANCE FORMATTING GUIDELINES

All legislative drafts must adhere to the following formatting standards before final reading:

1. HEADER: The top three lines (City, Ordinance No., and Title) must be Centered and Bolded.
2. PREAMBLE: All "WHEREAS" clauses must have increased line spacing (1.5 or Double spaced) to separate them clearly.
3. LEGISLATIVE MARKUP: 
   - All text additions (currently marked with ++text++) must be Underlined.
   - All text deletions (currently marked with --text--) must be Struck Through.
   - Remove all + and - marker symbols. Do NOT delete the old text itself!
4. CODE BLOCK INDENTATION: The actual municipal code text being amended (Items A, B, C, D, and E under Section 1) must be indented. Set the Left Margin to at least 0.5 inches (1.27 cm).
5. SIGNATURES: The signature block lines at the bottom (Mayor, Attest, City Clerk, and lines) must be Right-Aligned.
EOF
chown ga:ga /home/ga/Desktop/ordinance_formatting_rules.txt

# ------------------------------------------------------------------
# Create the unformatted draft ordinance using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Header ──
add_paragraph("City of Oakridge")
add_paragraph("Ordinance No. 2026-04")
add_paragraph("An Ordinance Amending the Zoning Code Regarding Accessory Dwelling Units")
add_paragraph("")

# ── Preambles ──
add_paragraph("WHEREAS, the City Council recognizes a housing shortage within the municipality;")
add_paragraph("WHEREAS, Accessory Dwelling Units (ADUs) provide an affordable housing option that integrates into existing neighborhoods;")
add_paragraph("WHEREAS, the Planning Commission held a public hearing on April 15, 2026, and recommended approval of the amendments;")
add_paragraph("WHEREAS, the City Council finds it in the public interest to ease ADU development restrictions;")
add_paragraph("")

# ── Body ──
add_paragraph("SECTION 1: Section 17.24.050 of the Municipal Code is hereby amended to read as follows:")
add_paragraph("")
add_paragraph("A. Definition: An Accessory Dwelling Unit is a --secondary-- ++subordinate++ dwelling unit located on the same lot as a primary single-family home.")
add_paragraph("B. Maximum Size: The total floor area of an attached or detached ADU shall not exceed --800-- ++1,200++ square feet.")
add_paragraph("C. Owner Occupancy: The property owner --shall-- ++is not required to++ occupy either the primary or the accessory dwelling.")
add_paragraph("D. Lot Coverage: The combined lot coverage of all structures shall not exceed --50%-- ++75%++ of the total lot area.")
add_paragraph("E. Parking: One off-street parking space --is required-- ++may be waived++ if the property is located within one-half mile of public transit.")
add_paragraph("")
add_paragraph("SECTION 2: This ordinance shall take effect 30 days after its passage.")
add_paragraph("")

# ── Signatures ──
add_paragraph("Passed and Approved this 12th day of May, 2026.")
add_paragraph("___________________________")
add_paragraph("Mayor Sarah Jenkins")
add_paragraph("Attest:")
add_paragraph("___________________________")
add_paragraph("City Clerk David Lin")

doc.save("/home/ga/Documents/draft_adu_ordinance.odt")
PYEOF

chown ga:ga /home/ga/Documents/draft_adu_ordinance.odt

# Launch Calligra Words and wait for window
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/draft_adu_ordinance.odt >/tmp/calligra.log 2>&1 < /dev/null &"

# Wait for window and maximize
wait_for_window "Calligra Words" 30
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Dismiss any recovery prompts
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take setup screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="