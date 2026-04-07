#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Forensic Audit Report Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

kill_calligra_processes
rm -f /home/ga/Documents/project_chariot_investigation.odt
rm -f /home/ga/Desktop/audit_formatting_guidelines.txt

# Create the formatting guidelines document
cat > /home/ga/Desktop/audit_formatting_guidelines.txt << 'EOF'
NEXUS SYSTEMS CORP. - FORENSIC AUDIT REPORTING GUIDELINES

1. Report Title: Must be Bold and at least 16pt font.
2. Main Sections: Use "Heading 1" style for Executive Summary, Investigation Scope, Findings, Transaction Analysis, and Internal Control Recommendations.
3. Subsections: Use "Heading 2" style for specific findings.
4. Transaction Analysis: Convert the raw transaction log (Date | Vendor | Invoice # | Amount | Flag) into a formatted table.
5. Internal Controls: Format the remediation steps as a bulleted or numbered list.
6. Implicated Entities: Systematically apply Bold formatting to every mention of "Apex Consulting LLC" and "Meridian Solutions" to highlight risk exposure.
7. Executive Summary: The body text of the Executive Summary must be justified.
EOF

chown ga:ga /home/ga/Desktop/audit_formatting_guidelines.txt

# Create the unformatted audit report using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title
add_paragraph("Project Chariot: Forensic Audit Report")
add_paragraph("Subject: Procurement Fraud Investigation - European Subsidiary")
add_paragraph("Date: October 14, 2025")
add_paragraph("Prepared by: Internal Audit & Forensic Accounting Team")
add_paragraph("")

# Executive Summary
add_paragraph("Executive Summary")
add_paragraph("Between January 2024 and September 2025, the internal audit team conducted a forensic investigation into procurement activities at the European subsidiary following whistle-blower allegations of fictitious vendor payments. The investigation confirmed a systematic pass-through billing scheme orchestrated by two procurement managers, resulting in a financial exposure of approximately €1.4 million. The scheme utilized two primary shell companies, Apex Consulting LLC and Meridian Solutions, to process fraudulent invoices just below the €50,000 secondary approval threshold. Immediate termination of implicated personnel and freezing of associated vendor accounts has been executed.")
add_paragraph("")

# Investigation Scope
add_paragraph("Investigation Scope")
add_paragraph("The audit team reviewed all procurement transactions processed by the regional office between January 1, 2024, and September 30, 2025. This included vendor master data changes, invoice approvals, payment disbursements, and email correspondence of the implicated managers. A threshold analysis was performed on all invoices between €45,000 and €49,999.")
add_paragraph("")

# Findings
add_paragraph("Findings")
add_paragraph("Finding 1: Fictitious Vendor Creation")
add_paragraph("The investigation identified that Apex Consulting LLC and Meridian Solutions were added to the vendor master file without undergoing the standard due diligence process. Both entities share the same registered address, which was identified as a virtual office in Cyprus. No service contracts or statements of work were found for either entity.")
add_paragraph("Finding 2: Invoice Splitting")
add_paragraph("To circumvent the €50,000 secondary approval requirement, the implicated managers engaged in systematic invoice splitting. For example, a single consulting engagement was billed as three separate €48,500 invoices submitted on consecutive days by Meridian Solutions. This pattern was repeated 14 times during the period under review.")
add_paragraph("")

# Transaction Analysis
add_paragraph("Transaction Analysis")
add_paragraph("The following is an excerpt of the fraudulent transactions processed:")
add_paragraph("Date | Vendor | Invoice # | Amount | Flag")
add_paragraph("2024-03-12 | Apex Consulting LLC | INV-1044 | €49,500 | No Contract")
add_paragraph("2024-03-15 | Apex Consulting LLC | INV-1045 | €48,200 | Split Invoice")
add_paragraph("2024-06-22 | Meridian Solutions | MS-2024-08 | €49,900 | High Risk")
add_paragraph("2024-06-23 | Meridian Solutions | MS-2024-09 | €49,900 | Split Invoice")
add_paragraph("2025-01-10 | Apex Consulting LLC | INV-2051 | €47,500 | No Deliverables")
add_paragraph("")

# Internal Control Recommendations
add_paragraph("Internal Control Recommendations")
add_paragraph("The following remediation steps must be implemented immediately:")
add_paragraph("Implement mandatory dual-approval for all new vendor onboarding regardless of initial contract value.")
add_paragraph("Deploy automated threshold-monitoring scripts to flag multiple invoices from the same vendor summing to over €50,000 within a 30-day period.")
add_paragraph("Conduct a comprehensive retroactive review of all vendors sharing virtual office addresses or lacking physical corporate locations.")
add_paragraph("Require documented Statements of Work (SOW) and verified deliverables before payment approval for all consulting services.")
add_paragraph("Establish an independent vendor management office (VMO) separate from procurement operations to eliminate segregation of duties conflicts.")
add_paragraph("")

doc.save("/home/ga/Documents/project_chariot_investigation.odt")
PYEOF

chown ga:ga /home/ga/Documents/project_chariot_investigation.odt
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority calligrawords /home/ga/Documents/project_chariot_investigation.odt >/dev/null 2>&1 &"
sleep 5

# Maximize and focus
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="