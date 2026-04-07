#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up ISO 9001 Audit Report Formatting Task ==="

# Clean up environment
kill_calligra_processes
install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
rm -f /home/ga/Documents/apex_iso_audit_report.odt
rm -f /home/ga/Desktop/qa_formatting_rules.txt

# ---------------------------------------------------------------------------
# Create the QA Formatting Rules Document
# ---------------------------------------------------------------------------
cat << 'EOF' > /home/ga/Desktop/qa_formatting_rules.txt
QA DEPARTMENT FORMATTING GUIDELINES FOR ISO AUDIT REPORTS

1. Document Title: Must be formatted as Bold, Centered, and at least 16pt font.
2. Main Sections (Audit Scope, Methodology, Executive Summary, Detailed Findings, CAPA Log): Format as Heading 1.
3. ISO Clause Subsections (e.g., Clause 7.1.5, Clause 8.4): Format as Heading 2.
4. Inline Clause References: Any mention of an ISO clause in the narrative text must be Italicized.
5. Severity Alerting:
   - Every instance of the exact phrase "MAJOR NON-CONFORMANCE" must be styled as Bold and Red text.
   - Every instance of the exact phrase "MINOR NON-CONFORMANCE" must be styled as Bold text (default color).
6. CAPA Log Table: The pipe-delimited (|) text at the end of the document must be converted into a formal 4-column table.
7. Table of Contents: Insert a TOC immediately following the Executive Summary section.
EOF
chown ga:ga /home/ga/Desktop/qa_formatting_rules.txt

# ---------------------------------------------------------------------------
# Create the Unformatted Audit Report (Plain Text Paragraphs)
# ---------------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add(text=""):
    doc.text.addElement(P(text=text))

# Title
add("ISO 9001:2015 Surveillance Audit Report")
add("Apex Machining Solutions")
add("Audit Date: October 10-12, 2025")
add("Lead Auditor: Sarah Jenkins, CQE")
add("")

# Sections
add("Audit Scope")
add("This surveillance audit covered the manufacturing, quality control, and shipping departments at the Apex Machining Solutions primary facility. The audit evaluated compliance against the ISO 9001:2015 standard.")
add("")

add("Methodology")
add("The audit was conducted through direct observation of manufacturing processes, personnel interviews, and sampling of quality records. Evidence was gathered to verify the effective implementation of the Quality Management System (QMS).")
add("")

add("Executive Summary")
add("Overall, Apex Machining Solutions demonstrates a commitment to quality. The QMS is generally well-maintained. However, critical vulnerabilities were identified in calibration tracking and product staging that require immediate corrective action. Two major non-conformances and three minor non-conformances were raised.")
add("")

add("Detailed Findings")
add("Clause 7.1.5 Monitoring and measuring resources")
add("During the inspection of Line 4 against Clause 7.1.5, three digital calipers (IDs: DC-104, DC-108, DC-112) were found in active use with calibration tags that expired two months ago. This is a MAJOR NON-CONFORMANCE as it directly impacts product measurement accuracy.")
add("")

add("Clause 7.5 Documented information")
add("Reviewing compliance with Clause 7.5, an outdated revision (Rev C) of Work Instruction WI-04 was found taped to the operator station on Line 2. The current active revision in the document control system is Rev E. This is a MINOR NON-CONFORMANCE.")
add("")

add("Clause 8.4 Control of externally provided processes, products and services")
add("As required by Clause 8.4, the annual supplier evaluation for critical raw material vendor 'SteelTech Inc' was not completed within the required timeframe. This is a MINOR NON-CONFORMANCE.")
add("")

add("Clause 8.5.2 Identification and traceability")
add("In violation of Clause 8.5.2, Batch #88492 aerospace components were found in the staging area without proper routing tags. Without clear identification, there is a risk of mixing conforming and non-conforming products. This is a MAJOR NON-CONFORMANCE.")
add("")

add("Clause 9.3 Management review")
add("Regarding Clause 9.3, the management review minutes from Q2 did not explicitly record mandatory outputs related to resource needs, though it was discussed. This is a MINOR NON-CONFORMANCE.")
add("")

add("CAPA Log")
add("Finding ID | Clause | Severity | Required Action")
add("CAPA-001 | 7.1.5 | MAJOR | Recalibrate all Line 4 digital calipers immediately.")
add("CAPA-002 | 7.5 | MINOR | Update Work Instruction WI-04 to Rev E at all stations.")
add("CAPA-003 | 8.4 | MINOR | Complete annual evaluation for SteelTech Inc.")
add("CAPA-004 | 8.5.2 | MAJOR | Implement tagging procedure for aerospace batches in staging.")
add("CAPA-005 | 9.3 | MINOR | Revise Q2 management review minutes to include resource needs.")

doc.save("/home/ga/Documents/apex_iso_audit_report.odt")
PYEOF

chown ga:ga /home/ga/Documents/apex_iso_audit_report.odt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/apex_iso_audit_report.odt"
sleep 5

# Maximize and Focus
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="