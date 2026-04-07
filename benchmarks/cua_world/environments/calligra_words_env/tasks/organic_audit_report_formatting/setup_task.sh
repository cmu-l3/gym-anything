#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Organic Audit Report Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/sunny_creek_audit_report.odt
rm -f /home/ga/Desktop/certifier_formatting_rules.txt

# ------------------------------------------------------------------
# Create the formatting specification
# ------------------------------------------------------------------
cat > /home/ga/Desktop/certifier_formatting_rules.txt << 'EOF'
CERTIFIER FORMATTING RULES FOR INSPECTION REPORTS
-------------------------------------------------
1. Title: Must be Centered, Bold, and at least 16pt font.
2. Section Headings: The 6 main sections must use "Heading 1" style.
3. Subsections: The 4 subsections must use "Heading 2" style.
4. Crop Data: Any comma-separated crop lists must be converted into a structured Table.
5. Input Materials: Items listed as inputs must be formatted as a Bulleted List.
6. Regulatory Citations: Any reference starting with "7 CFR § 205." MUST be Bolded for committee review.
7. Body Paragraphs: All standard body text must be Justified.
8. Table of Contents: A generated TOC must be placed immediately following the title.
EOF
chown ga:ga /home/ga/Desktop/certifier_formatting_rules.txt

# ------------------------------------------------------------------
# Create the unformatted report using odfpy
# ALL content is plain P elements — no heading styles, no bold, etc.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Title ──
add_paragraph("Sunny Creek Organics - Annual On-Site Inspection Report")
add_paragraph("")

# ── General Info ──
add_paragraph("General Information")
add_paragraph(
    "The inspection was conducted on August 14, 2025. The operation is located "
    "at 1234 Valley Road, Springfield. The primary contact is Jane Doe. All "
    "records were made available during the visit."
)
add_paragraph("Requested crop certification data:")
add_paragraph("Crop, Acreage, Estimated Yield")
add_paragraph("Carrots, 12, 5000 lbs")
add_paragraph("Tomatoes, 8, 8000 lbs")
add_paragraph("Lettuce, 5, 2000 lbs")
add_paragraph("")

# ── Organic System Plan Verification ──
add_paragraph("Organic System Plan Verification")
add_paragraph(
    "The producer's organic system plan (OSP) accurately reflects the practices "
    "observed during the on-site inspection. All field maps are up to date and "
    "correctly identify adjoining land uses."
)
add_paragraph("")

# ── Natural Resources ──
add_paragraph("Natural Resources")
add_paragraph("Buffer Zones")
add_paragraph(
    "The producer maintains a 25-foot buffer zone along the eastern property "
    "boundary to prevent unintended application of prohibited substances from "
    "the neighboring conventional farm."
)
add_paragraph("")

# ── Seeds and Planting Stock ──
add_paragraph("Seeds and Planting Stock")
add_paragraph(
    "All seeds used during the current organic production cycle were sourced "
    "organically. Commercial availability searches were documented for the three "
    "varieties where organic seed was not used."
)
add_paragraph("")

# ── Crop Pest and Disease Management ──
add_paragraph("Crop Pest and Disease Management")
add_paragraph("Input Materials")
add_paragraph("The following input materials were requested for verification:")
add_paragraph("Fish emulsion")
add_paragraph("Neem oil")
add_paragraph("Compost")
add_paragraph("Liquid kelp")
add_paragraph("")
add_paragraph("Crop Rotation")
add_paragraph(
    "The producer demonstrated a crop rotation practice that includes a minimum "
    "of three different crop families and incorporates a winter cover crop to "
    "manage soil health and pest cycles."
)
add_paragraph("")

# ── Audit Trail and Traceability ──
add_paragraph("Audit Trail and Traceability")
add_paragraph("Non-Compliance Citations")
add_paragraph(
    "The inspector noted a minor non-compliance regarding seed search "
    "documentation, in violation of 7 CFR § 205.201. Another issue was found "
    "with compost application records, citing 7 CFR § 205.203. A discrepancy in "
    "crop rotation records relates to 7 CFR § 205.205. Finally, the certification "
    "fee payment was delayed according to 7 CFR § 205.400."
)

doc.save("/home/ga/Documents/sunny_creek_audit_report.odt")
PYEOF

chown ga:ga /home/ga/Documents/sunny_creek_audit_report.odt

# Record the initial modified time of the document
stat -c %Y /home/ga/Documents/sunny_creek_audit_report.odt > /tmp/initial_mtime.txt

# Start Calligra Words
launch_calligra_document "/home/ga/Documents/sunny_creek_audit_report.odt"

# Wait for application window
wait_for_window "Calligra Words" 30

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Dismiss popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="