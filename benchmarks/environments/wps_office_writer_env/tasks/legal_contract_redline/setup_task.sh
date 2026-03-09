#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Legal Contract Redline Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the messy draft contract document
# Based on standard vendor services agreement structure (ABA Model Agreements pattern)
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title - centered but NO heading style (agent must fix)
title = doc.add_paragraph("VENDOR SERVICES AGREEMENT")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.bold = True
    run.font.size = Pt(16)

doc.add_paragraph("")

# Introductory paragraph
doc.add_paragraph(
    'This Vendor Services Agreement (the "Agreement") is entered into as of March 1, 2024 '
    '(the "Effective Date"), by and between CloudFirst Industries, LLC, a Delaware limited '
    'liability company with its principal offices at 200 Park Avenue, Suite 1800, New York, '
    'NY 10166 (the "Client"), and Meridian Technology Solutions, Inc., a California '
    'corporation with its principal offices at 500 Technology Drive, San Jose, CA 95110 '
    '(the "Vendor").'
)

# Recitals - no special formatting (should be styled)
doc.add_paragraph(
    "WHEREAS, Client desires to engage Vendor to provide certain technology consulting "
    "and software development services as more particularly described herein; and"
)
doc.add_paragraph(
    "WHEREAS, Vendor represents that it has the expertise, qualified personnel, and "
    "resources necessary to perform such services in a professional manner;"
)
doc.add_paragraph(
    "NOW, THEREFORE, in consideration of the mutual covenants and agreements contained "
    "herein, and for other good and valuable consideration, the receipt and sufficiency "
    "of which are hereby acknowledged, the parties agree as follows:"
)

# Section 1: DEFINITIONS - WRONG heading level (Heading 2 instead of 1)
doc.add_heading("1. DEFINITIONS", level=2)
doc.add_paragraph(
    '"Agreement" means this Vendor Services Agreement, including all exhibits, '
    'schedules, and amendments hereto.'
)
doc.add_paragraph(
    '"Confidential Information" means any proprietary, non-public, or trade secret '
    'information disclosed by either party to the other party in connection with this '
    'Agreement, whether disclosed orally, in writing, or by inspection.'
)
doc.add_paragraph(
    '"Effective Date" means March 1, 2024, the date first written above.'
)
# MISSING definitions: "Deliverables", "Service Level Agreement", "Term" are used later

# Section 2: SCOPE OF SERVICES - correct heading level
doc.add_heading("2. SCOPE OF SERVICES", level=1)
doc.add_paragraph(
    "2.1 Meridian Tech shall provide the following technology consulting and software "
    "development services to Client as described in this Agreement and any applicable "
    "Statements of Work (collectively, the \"Services\")."
)
doc.add_paragraph(
    "2.2 The Vendor shall assign qualified personnel to perform the Services in "
    "accordance with the Service Level Agreement and industry best practices. All "
    "personnel assigned shall have relevant experience and certifications."
)
doc.add_paragraph(
    "2.3 MERIDIAN shall provide weekly written status reports to Client detailing "
    "progress against milestones, issues encountered, risks identified, and resource "
    "utilization metrics."
)

# Section 3: DELIVERABLES - Normal style with bold, NOT a heading
p = doc.add_paragraph("3. DELIVERABLES AND ACCEPTANCE")
p.runs[0].bold = True

doc.add_paragraph(
    "3.1 The Vendor shall deliver the Deliverables set forth in the table below in "
    "accordance with the specified timeline. Each Deliverable shall be subject to "
    "Client's acceptance procedures."
)

# Deliverables table - NO formatting (no bold headers, no shading)
table = doc.add_table(rows=5, cols=4)
table.style = 'Table Grid'
cells = table.rows[0].cells
cells[0].text = "Deliverable"
cells[1].text = "Description"
cells[2].text = "Due Date"
cells[3].text = "Acceptance Criteria"

data = [
    ["Platform Architecture Document", "Complete system architecture and design specifications", "April 15, 2024", "Approved by Client CTO"],
    ["MVP Release", "Minimum viable product with core features deployed", "June 30, 2024", "Passes User Acceptance Testing"],
    ["API Integration Layer", "Third-party API integration with documentation", "August 15, 2024", "All endpoints functional per spec"],
    ["Final Production Release", "Production-ready platform with full documentation", "October 31, 2024", "Sign-off from all stakeholders"],
]
for i, row_data in enumerate(data, 1):
    cells = table.rows[i].cells
    for j, text in enumerate(row_data):
        cells[j].text = text

doc.add_paragraph("")

# Section 4: COMPENSATION - WRONG heading level (Heading 2 instead of 1)
doc.add_heading("4. COMPENSATION AND PAYMENT TERMS", level=2)
doc.add_paragraph(
    "4.1 Client shall pay Meridian Technology Solutions a total fixed fee of Two Million "
    "Four Hundred Thousand Dollars ($2,400,000.00) for the Services described in this "
    "Agreement, payable in twelve (12) equal monthly installments of Two Hundred "
    "Thousand Dollars ($200,000.00)."
)
doc.add_paragraph(
    "4.2 MERIDIAN shall submit detailed invoices on the first business day of each "
    "calendar month. Client shall pay all undisputed invoices within thirty (30) days "
    "of receipt. Disputed amounts shall be resolved pursuant to Section 8.2."
)

# Randomly centered paragraph (formatting error)
p = doc.add_paragraph(
    "4.3 Late payments shall accrue interest at the lesser of: (a) one and one-half "
    "percent (1.5%) per month; or (b) the maximum rate permitted by applicable law."
)
p.alignment = WD_ALIGN_PARAGRAPH.CENTER  # WRONG

# Section 5: TERM AND TERMINATION - correct heading level
doc.add_heading("5. TERM AND TERMINATION", level=1)
doc.add_paragraph(
    "5.1 The Term of this Agreement shall commence on the Effective Date and shall "
    "continue for a period of twelve (12) months, unless earlier terminated as "
    "provided in this Section 5."
)
doc.add_paragraph(
    "5.2 Either party may terminate this Agreement for cause upon thirty (30) days' "
    "written notice to the other party if such other party materially breaches any "
    "provision of this Agreement and fails to cure such breach within said notice period."
)
doc.add_paragraph(
    "5.3 Client may terminate this Agreement for convenience upon sixty (60) days' "
    "prior written notice to Meridian Tech, subject to payment for Services rendered "
    "through the effective date of termination."
)

# Section 6: CONFIDENTIALITY - centered AND Normal style (two errors)
p = doc.add_paragraph("6. CONFIDENTIALITY")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER  # WRONG
p.runs[0].bold = True

doc.add_paragraph(
    "6.1 Each party agrees to hold in strict confidence all Confidential Information "
    "received from the other party and to use such information solely for the purposes "
    "contemplated by this Agreement. Neither party shall disclose Confidential "
    "Information to any third party without prior written consent."
)

# Random italic paragraph (formatting error)
p = doc.add_paragraph(
    "6.2 The obligations of confidentiality set forth in this Section 6 shall survive "
    "the expiration or termination of this Agreement for a period of three (3) years "
    "following such expiration or termination."
)
for run in p.runs:
    run.italic = True  # WRONG

# Section 7: LIMITATION OF LIABILITY - correct heading
doc.add_heading("7. LIMITATION OF LIABILITY", level=1)
doc.add_paragraph(
    "7.1 IN NO EVENT SHALL MERIDIAN TECH BE LIABLE TO CLIENT FOR ANY INDIRECT, "
    "INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT "
    "LIMITED TO LOSS OF PROFITS, DATA, OR BUSINESS OPPORTUNITIES, ARISING OUT OF "
    "OR RELATED TO THIS AGREEMENT."
)
doc.add_paragraph(
    "7.2 The total aggregate liability of the Vendor under this Agreement shall not "
    "exceed the total fees actually paid by Client to the Vendor during the twelve (12) "
    "months immediately preceding the event giving rise to such liability claim."
)

# Section 8: GENERAL PROVISIONS - correct heading
doc.add_heading("8. GENERAL PROVISIONS", level=1)

# Sub-sections with mixed formatting errors
p = doc.add_paragraph(
    "8.1 Governing Law. This Agreement shall be governed by and construed in accordance "
    "with the laws of the State of New York, without regard to its conflict of laws "
    "principles or provisions."
)
for run in p.runs:
    run.italic = True  # WRONG

p = doc.add_paragraph(
    "8.2 Dispute Resolution. Any dispute, claim, or controversy arising under or "
    "relating to this Agreement shall be resolved through binding arbitration "
    "administered by the American Arbitration Association in New York, New York."
)
for run in p.runs:
    run.bold = True
    run.italic = True  # WRONG

doc.add_paragraph(
    "8.3 Notices. All notices required or permitted under this Agreement shall be "
    "in writing and shall be deemed given when delivered personally, sent by certified "
    "mail (return receipt requested), or sent by overnight courier."
)

doc.add_paragraph(
    "8.4 Assignment. Neither party may assign or transfer this Agreement or any rights "
    "or obligations hereunder without the prior written consent of the other party, "
    "except that either party may assign this Agreement in connection with a merger, "
    "acquisition, or sale of substantially all of its assets."
)

doc.add_paragraph(
    "8.5 Entire Agreement. This Agreement, together with all exhibits and schedules "
    "attached hereto, constitutes the entire agreement between the parties with respect "
    "to the subject matter hereof and supersedes all prior and contemporaneous "
    "agreements, understandings, negotiations, and discussions, whether oral or written."
)

doc.add_paragraph(
    "8.6 Amendments. No amendment, modification, or waiver of any provision of this "
    "Agreement shall be effective unless set forth in a written instrument signed by "
    "duly authorized representatives of both parties."
)

doc.add_paragraph(
    "8.7 Severability. If any provision of this Agreement is held to be invalid, "
    "illegal, or unenforceable, the remaining provisions shall continue in full "
    "force and effect."
)

# NO SIGNATURE BLOCK - agent must add one

doc.save("/home/ga/Documents/vendor_agreement_draft.docx")
print("Created messy draft vendor agreement with deliberate formatting issues")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/vendor_agreement_draft.docx
sudo chmod 666 /home/ga/Documents/vendor_agreement_draft.docx

# Record baseline timestamp
date +%s > /tmp/legal_contract_redline_start_ts

# Launch WPS Writer with the document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORMTHEME=gtk2 wps /home/ga/Documents/vendor_agreement_draft.docx > /tmp/wps_task.log 2>&1 &"

# Wait for WPS to start
if ! wait_for_process "wps" 20; then
    echo "ERROR: WPS Writer failed to start"
    cat /tmp/wps_task.log
fi

echo "Waiting for WPS window..."
sleep 5

# EULA dismissal loop
max_eula_attempts=10
eula_attempt=0
document_visible=false

while [ $eula_attempt -lt $max_eula_attempts ] && [ "$document_visible" = "false" ]; do
    eula_attempt=$((eula_attempt + 1))
    echo "Verifying application state (attempt $eula_attempt/$max_eula_attempts)..."

    if wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        echo "EULA dialog detected, dismissing..."
        dismiss_wps_eula 3
        sleep 2
    fi

    dismiss_wps_dialogs
    sleep 1

    if wmctrl -l | grep -qi "vendor_agreement\|Writer" && ! wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        echo "Document window is visible!"
        document_visible=true
    else
        echo "Document window not yet visible, waiting..."
        sleep 2
    fi
done

# Wait for window
if ! wait_for_window "WPS Writer\|vendor_agreement\|Writer" 20; then
    echo "Warning: WPS window not detected"
    wmctrl -l
fi

sleep 5

# Focus WPS window
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 1
fi

# Ensure document is open
check_document_open() {
    local win_list=$(wmctrl -l 2>/dev/null)
    if echo "$win_list" | grep -qi "vendor_agreement"; then return 0; fi
    if echo "$win_list" | grep -qi "\.docx"; then return 0; fi
    if echo "$win_list" | grep -i "Writer" | grep -qiv "WPS Office$"; then return 0; fi
    return 1
}

max_open_attempts=5
open_attempt=0
document_opened=false

while [ $open_attempt -lt $max_open_attempts ] && [ "$document_opened" = "false" ]; do
    open_attempt=$((open_attempt + 1))
    if check_document_open; then
        document_opened=true
        break
    fi
    echo "Document not open, trying xdg-open..."
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/vendor_agreement_draft.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
    if check_document_open; then
        document_opened=true
        break
    fi
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/vendor_agreement_draft.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
done

sleep 3
DISPLAY=:1 xdotool key ctrl+Home
sleep 1

# Dismiss remaining dialogs
for i in 1 2 3; do
    DISPLAY=:1 wmctrl -c "System Check" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done
sleep 1

take_screenshot /tmp/legal_contract_redline_start_screenshot.png

echo "=== Legal Contract Redline Task Setup Complete ==="
