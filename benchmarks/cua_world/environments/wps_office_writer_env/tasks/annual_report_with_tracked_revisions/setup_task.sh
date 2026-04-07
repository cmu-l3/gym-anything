#!/bin/bash
# set -euo pipefail

echo "=== Setting up Annual Report with Tracked Revisions Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/annual_report_start_ts

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents

# Delete any stale output file BEFORE recording timestamp
rm -f /home/ga/Documents/novabio_annual_report_final.docx 2>/dev/null || true
rm -f /tmp/annual_report_output.docx 2>/dev/null || true
rm -f /tmp/annual_report_result.json 2>/dev/null || true

# Verify python-docx is available
python3 -c "import docx" 2>/dev/null || {
    echo "python-docx not found, installing..."
    pip3 install --break-system-packages python-docx 2>/dev/null || \
    pip3 install python-docx || {
        echo "ERROR: Failed to install python-docx"
        exit 1
    }
}

# Create the draft document with python-docx
echo "Creating draft document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()
style = doc.styles['Normal']
style.font.name = 'Times New Roman'
style.font.size = Pt(12)

# ============================================================
# COVER PAGE — no heading style, just formatted text
# ============================================================
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run("NovaBio Therapeutics, Inc.")
run.bold = True
run.font.size = Pt(18)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run("Annual Report to Shareholders")
run.font.size = Pt(14)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run("Fiscal Year Ended December 31, 2024")
run.font.size = Pt(12)

# blank lines for spacing
doc.add_paragraph("")
doc.add_paragraph("")

# ============================================================
# SECTION 1: Letter to Shareholders
# DELIBERATELY set as Heading 2 (WRONG — should be Heading 1)
# ============================================================
doc.add_heading("Letter to Shareholders", level=2)

doc.add_paragraph(
    "Dear Fellow Shareholders, Fiscal year 2024 marked a transformative period "
    "for NovaBio Therapeutics. We achieved total revenue of $142.3M, representing "
    "a 14.8% increase over the prior year, driven by strong demand across our "
    "oncology and immunology portfolios."
)

doc.add_paragraph(
    "Our research and development expenditure of $68.1M reflects our continued "
    "commitment to innovation. We advanced our lead compound NB-4012 through "
    "Phase III clinical trials for non-small cell lung cancer, with topline "
    "data expected in Q2 2025."
)

doc.add_paragraph(
    "Looking ahead, we remain focused on disciplined capital allocation and "
    "pipeline diversification. I am confident that NovaBio is well positioned "
    "to deliver sustainable long-term growth for our shareholders."
)

# ============================================================
# SECTION 2: Company Overview
# Correctly set as Heading 1
# ============================================================
doc.add_heading("Company Overview", level=1)

doc.add_paragraph(
    "NovaBio Therapeutics, Inc. is a commercial-stage biopharmaceutical company "
    "founded in 2011 and headquartered in Cambridge, Massachusetts. We discover, "
    "develop, and commercialize novel therapeutics for oncology, immunology, and "
    "rare diseases."
)

doc.add_paragraph(
    "As of December 31, 2024, the Company employed approximately 1,200 full-time "
    "employees across our Cambridge headquarters, San Diego research campus, and "
    "European commercial operations in Basel, Switzerland."
)

# ============================================================
# SECTION 3: Financial Highlights
# DELIBERATELY set as Normal + Bold (WRONG — should be Heading 1)
# ============================================================
p = doc.add_paragraph()
run = p.add_run("Financial Highlights")
run.bold = True
run.font.size = Pt(14)

# Subsection — no heading style applied (should be Heading 2)
p = doc.add_paragraph()
run = p.add_run("Revenue Breakdown")
run.bold = True

doc.add_paragraph(
    "Total revenue for fiscal year 2024 reached $142.3M, distributed across "
    "our four operating segments as follows:"
)

# Pipe-delimited data block (NOT a table — agent must convert)
doc.add_paragraph("Segment | FY2024 ($M) | FY2023 ($M) | YoY Change (%)")
doc.add_paragraph("Oncology Therapeutics | 58.2 | 51.7 | +12.6")
doc.add_paragraph("Immunology Portfolio | 47.1 | 42.3 | +11.3")
doc.add_paragraph("Rare Disease Programs | 37.0 | 30.8 | +20.1")
doc.add_paragraph("Diagnostics & Services | 5.5 | 3.9 | +41.0")

# Another subsection — no heading style (should be Heading 2)
p = doc.add_paragraph()
run = p.add_run("Operating Expenses")
run.bold = True

doc.add_paragraph(
    "Research and development expenses totaled $68.1M, representing 47.9% of "
    "total revenue. Selling, general, and administrative expenses were $31.2M."
)

# ============================================================
# SECTION 4: Research Pipeline
# Correctly set as Heading 1
# ============================================================
doc.add_heading("Research Pipeline", level=1)

# Subsection — no heading style (should be Heading 2)
p = doc.add_paragraph()
run = p.add_run("Clinical Programs")
run.bold = True

doc.add_paragraph(
    "NB-4012 (anti-PD-L1/VEGF bispecific): Currently in Phase III registration "
    "trial (NOVA-301) for first-line treatment of non-small cell lung cancer. "
    "Enrollment of 680 patients completed in September 2024."
)

doc.add_paragraph(
    "NB-7803 (IL-23 inhibitor): Phase III trial (NOVA-302) ongoing for moderate-to-"
    "severe ulcerative colitis. Interim analysis demonstrated statistically "
    "significant improvement in clinical remission at Week 12."
)

# Subsection — no heading style (should be Heading 2)
p = doc.add_paragraph()
run = p.add_run("Preclinical Programs")
run.bold = True

doc.add_paragraph(
    "Our preclinical pipeline includes NB-9100, a novel ADC targeting Trop-2 for "
    "triple-negative breast cancer, and NB-9205, a CRISPR-based gene therapy "
    "candidate for sickle cell disease. Both programs are expected to file IND "
    "applications in the second half of 2025."
)

# ============================================================
# SECTION 5: Consolidated Financial Statements
# DELIBERATELY set as Heading 2 (WRONG — should be Heading 1)
# ============================================================
doc.add_heading("Consolidated Financial Statements", level=2)

doc.add_paragraph(
    "The following condensed financial data is derived from our audited "
    "consolidated financial statements. Total revenue of $142.3M and R&D "
    "expenditure of $68.1M are summarized below."
)

# Income statement as pipe-delimited text (agent must convert to table)
doc.add_paragraph("Line Item | FY2024 ($M) | FY2023 ($M)")
doc.add_paragraph("Total Revenue | 142.3 | 128.7")
doc.add_paragraph("Cost of Goods Sold | (38.4) | (35.1)")
doc.add_paragraph("Gross Profit | 103.9 | 93.6")
doc.add_paragraph("Research & Development | (68.1) | (61.2)")
doc.add_paragraph("Selling, General & Admin | (31.2) | (28.7)")
doc.add_paragraph("Operating Income | 4.6 | 3.7")
doc.add_paragraph("Interest & Other Income | 2.8 | 1.9")
doc.add_paragraph("Net Income | 5.9 | 4.2")

doc.add_paragraph("")

# Balance sheet as pipe-delimited text
doc.add_paragraph("Balance Sheet Item | FY2024 ($M) | FY2023 ($M)")
doc.add_paragraph("Cash & Equivalents | 89.4 | 72.1")
doc.add_paragraph("Total Current Assets | 134.7 | 112.3")
doc.add_paragraph("Total Assets | 298.5 | 261.4")
doc.add_paragraph("Total Current Liabilities | 42.1 | 38.6")
doc.add_paragraph("Long-Term Debt | 75.0 | 75.0")
doc.add_paragraph("Total Stockholders Equity | 167.2 | 135.8")

# ============================================================
# SECTION 6: Risk Factors and Forward-Looking Statements
# Correctly set as Heading 1
# ============================================================
doc.add_heading("Risk Factors and Forward-Looking Statements", level=1)

doc.add_paragraph(
    "Investing in our securities involves significant risks. Our business is "
    "subject to risks related to regulatory approval processes, clinical trial "
    "outcomes, intellectual property protection, and competitive market dynamics. "
    "The results for NB-4012 and NB-7803 remain subject to the inherent "
    "uncertainties of clinical development."
)

doc.add_paragraph(
    "Market risks include potential generic competition for our marketed products, "
    "pricing pressure from government and private payers, and foreign currency "
    "fluctuations affecting our European operations."
)

doc.add_paragraph(
    "This Annual Report contains forward-looking statements within the meaning of "
    "Section 27A of the Securities Act of 1933 and Section 21E of the Securities "
    "Exchange Act of 1934. These statements involve known and unknown risks, "
    "uncertainties, and other factors that may cause actual results to differ "
    "materially from those expressed or implied. Shareholders are cautioned not "
    "to place undue reliance on forward-looking statements."
)

doc.save("/home/ga/Documents/novabio_annual_report_draft.docx")
print("Draft document created successfully")
PYEOF

# Verify file was created
if [ ! -f /home/ga/Documents/novabio_annual_report_draft.docx ]; then
    echo "ERROR: Draft document was not created!"
    exit 1
fi

# Set correct ownership and permissions
sudo chown ga:ga /home/ga/Documents/novabio_annual_report_draft.docx
sudo chmod 666 /home/ga/Documents/novabio_annual_report_draft.docx

echo "Draft document created and verified"

# Kill any existing WPS instances
pkill -x wps 2>/dev/null || true
sleep 2

# Launch WPS Writer with the document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/novabio_annual_report_draft.docx > /tmp/wps_task.log 2>&1 &"

# Wait for WPS process to start
if ! wait_for_process "wps" 20; then
    echo "ERROR: WPS Writer failed to start"
    cat /tmp/wps_task.log 2>/dev/null || true
fi

sleep 5

# Dismiss EULA and first-run dialogs
echo "Dismissing EULA and startup dialogs..."
max_eula_attempts=10
eula_attempt=0
wps_visible=false

while [ $eula_attempt -lt $max_eula_attempts ] && [ "$wps_visible" = "false" ]; do
    eula_attempt=$((eula_attempt + 1))
    echo "Verifying application state (attempt $eula_attempt/$max_eula_attempts)..."

    if wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        echo "EULA dialog detected, dismissing..."
        dismiss_wps_eula 3
        sleep 2
    fi

    dismiss_wps_dialogs
    sleep 1

    if wmctrl -l | grep -qi "Writer\|WPS" && ! wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        echo "WPS Writer window is visible!"
        wps_visible=true
    else
        echo "WPS Writer window not yet visible, waiting..."
        sleep 2
    fi
done

if [ "$wps_visible" = "false" ]; then
    echo "WARNING: Could not confirm WPS Writer visible after $max_eula_attempts attempts"
    echo "Current windows:"
    wmctrl -l
fi

# Wait for any WPS window
wait_for_window "WPS Writer\|WPS\|Writer" 20 || true

sleep 3

# Focus and maximize the WPS window
echo "Focusing WPS window..."
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
    sleep 1
fi

# Ensure document is actually open (not just WPS start screen)
echo "Ensuring document is open..."
max_open_attempts=5
open_attempt=0
document_opened=false

while [ $open_attempt -lt $max_open_attempts ] && [ "$document_opened" = "false" ]; do
    open_attempt=$((open_attempt + 1))
    echo "Document open attempt $open_attempt/$max_open_attempts..."

    if wmctrl -l | grep -qi "novabio_annual_report_draft"; then
        echo "Document is open!"
        document_opened=true
        break
    fi

    echo "Document not yet open, trying to open it..."

    # Method 1: xdg-open
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/novabio_annual_report_draft.docx" &
    sleep 4
    dismiss_wps_dialogs
    sleep 2

    if wmctrl -l | grep -qi "novabio_annual_report_draft"; then
        echo "xdg-open succeeded!"
        document_opened=true
        break
    fi

    # Method 2: Click Documents in sidebar then double-click file
    DISPLAY=:1 xdotool mousemove 247 333
    sleep 0.3
    DISPLAY=:1 xdotool click 1
    sleep 3
    DISPLAY=:1 xdotool mousemove 750 450
    sleep 0.3
    DISPLAY=:1 xdotool click --repeat 2 --delay 200 1
    sleep 3

    if wmctrl -l | grep -qi "novabio_annual_report_draft"; then
        echo "Sidebar navigation succeeded!"
        document_opened=true
        break
    fi

    # Method 3: Ctrl+O file dialog
    DISPLAY=:1 xdotool key ctrl+o
    sleep 2
    DISPLAY=:1 xdotool type "/home/ga/Documents/novabio_annual_report_draft.docx"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 4

    if wmctrl -l | grep -qi "novabio_annual_report_draft"; then
        echo "Ctrl+O succeeded!"
        document_opened=true
        break
    fi

    dismiss_wps_dialogs
    sleep 1
done

if [ "$document_opened" = "false" ]; then
    echo "WARNING: Could not confirm document is open after $max_open_attempts attempts"
    echo "Current windows:"
    wmctrl -l
fi

# Wait for document to fully render
sleep 3

# Move cursor to beginning of document
DISPLAY=:1 xdotool key ctrl+Home
sleep 0.5

# Dismiss any remaining dialogs
for i in 1 2 3; do
    DISPLAY=:1 wmctrl -c "System Check" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done
sleep 1

# Take verification screenshot
DISPLAY=:1 scrot /tmp/task_setup_verification.png 2>/dev/null || true

# Final check
final_windows=$(wmctrl -l 2>/dev/null)
if echo "$final_windows" | grep -qi "Writer\|WPS"; then
    if echo "$final_windows" | grep -qi "License Agreement\|Kingsoft"; then
        echo "WARNING: EULA dialog still visible at task start!"
    else
        echo "SUCCESS: WPS Writer window confirmed visible"
    fi
else
    echo "WARNING: WPS Writer window not detected in final check"
fi

echo "=== Annual Report Task Setup Complete ==="
