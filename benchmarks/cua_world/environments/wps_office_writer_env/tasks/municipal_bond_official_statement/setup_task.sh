#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Municipal Bond Official Statement Task ==="

sudo -u ga mkdir -p /home/ga/Documents

python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Cover page — no heading style, not properly formatted
title = doc.add_paragraph("OFFICIAL STATEMENT")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.bold = True
    run.font.size = Pt(16)

doc.add_paragraph("")

p = doc.add_paragraph("$45,000,000")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in p.runs:
    run.bold = True
    run.font.size = Pt(14)

p = doc.add_paragraph("CITY OF GREENFIELD, STATE OF COLUMBIA")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in p.runs:
    run.bold = True
    run.font.size = Pt(12)

p = doc.add_paragraph("General Obligation Bonds, Series 2024A")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in p.runs:
    run.font.size = Pt(12)

doc.add_paragraph("")

p = doc.add_paragraph(
    "Dated: October 1, 2024                    Due: October 1, as shown on inside cover"
)
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph("")

# Bond description — no heading
doc.add_paragraph(
    "The Bonds are being issued by the City of Greenfield (the 'City' or 'Issuer') for "
    "the purpose of financing capital improvements including road reconstruction, water "
    "treatment facility upgrades, and municipal building renovations. The Bonds constitute "
    "general obligations of the City, payable from ad valorem property taxes levied on all "
    "taxable property within the City without limitation as to rate or amount."
)

# MATURITY SCHEDULE — table with WRONG total
doc.add_heading("MATURITY SCHEDULE", level=2)  # Should be level 1

table = doc.add_table(rows=12, cols=5)
table.style = 'Table Grid'
headers = ["Maturity Date", "Principal Amount", "Interest Rate", "Yield", "CUSIP"]
for i, h in enumerate(headers):
    table.rows[0].cells[i].text = h

maturity_data = [
    ["10/01/2025", "$2,000,000", "4.00%", "3.25%", "396XXX AA1"],
    ["10/01/2026", "$2,000,000", "4.00%", "3.40%", "396XXX AB9"],
    ["10/01/2027", "$2,500,000", "4.25%", "3.55%", "396XXX AC7"],
    ["10/01/2028", "$2,500,000", "4.25%", "3.65%", "396XXX AD5"],
    ["10/01/2029", "$3,000,000", "4.50%", "3.80%", "396XXX AE3"],
    ["10/01/2030", "$3,000,000", "4.50%", "3.90%", "396XXX AF0"],
    ["10/01/2034", "$5,000,000", "4.75%", "4.10%", "396XXX AG8"],
    ["10/01/2039", "$10,000,000", "5.00%", "4.35%", "396XXX AH6"],
    ["10/01/2044", "$15,000,000", "5.00%", "4.50%", "396XXX AJ2"],
]
for i, row_data in enumerate(maturity_data, 1):
    for j, text in enumerate(row_data):
        table.rows[i].cells[j].text = text

# ERROR 1: Wrong total ($43,500,000 instead of $45,000,000)
total_row = table.rows[10]
total_row.cells[0].text = "TOTAL"
total_row.cells[1].text = "$43,500,000"  # WRONG — should be $45,000,000
total_row.cells[2].text = ""
total_row.cells[3].text = ""
total_row.cells[4].text = ""

# Last row for note
table.rows[11].cells[0].text = ""
table.rows[11].cells[1].text = "(Plus accrued interest from October 1, 2024)"
table.rows[11].cells[2].text = ""
table.rows[11].cells[3].text = ""
table.rows[11].cells[4].text = ""

doc.add_paragraph("")

# SECURITY AND SOURCES OF PAYMENT — correct heading
doc.add_heading("SECURITY AND SOURCES OF PAYMENT", level=1)
doc.add_paragraph(
    "The Bonds are general obligations of the City. The City has pledged its full faith "
    "and credit and has covenanted to levy ad valorem property taxes on all taxable property "
    "within the City sufficient to pay the principal of and interest on the Bonds as and when "
    "due, without limitation as to rate or amount."
)

# ERROR 2: Wrong assessed valuation (should include current year)
doc.add_paragraph(
    "The City's total assessed valuation for tax year 2023 is $3,847,291,000. The estimated "
    "full market value is approximately $5,124,388,000. The ratio of assessed to full value "
    "is 75.1%."
)

# DEBT SERVICE SCHEDULE
doc.add_heading("DEBT SERVICE SCHEDULE", level=1)

ds_table = doc.add_table(rows=6, cols=4)
ds_table.style = 'Table Grid'
ds_headers = ["Fiscal Year", "Principal", "Interest", "Total Debt Service"]
for i, h in enumerate(ds_headers):
    ds_table.rows[0].cells[i].text = h

ds_data = [
    ["2025", "$2,000,000", "$2,115,000", "$4,115,000"],
    ["2026", "$2,000,000", "$2,035,000", "$4,035,000"],
    ["2027", "$2,500,000", "$1,950,000", "$4,450,000"],
    ["2028", "$2,500,000", "$1,843,750", "$4,343,750"],
    # ERROR 3: Wrong total in debt service
    ["TOTAL", "$9,000,000", "$7,943,750", "$16,443,750"],
]
for i, row_data in enumerate(ds_data, 1):
    for j, text in enumerate(row_data):
        ds_table.rows[i].cells[j].text = text

doc.add_paragraph("")

# FINANCIAL INFORMATION — Heading 2 (should be Heading 1)
doc.add_heading("FINANCIAL INFORMATION", level=2)

doc.add_paragraph(
    "The City operates on a fiscal year basis from July 1 through June 30. The City's "
    "General Fund budget for FY 2024-2025 totals $127,450,000. The City has maintained "
    "an unassigned General Fund balance of not less than 15% of operating expenditures "
    "for each of the past five fiscal years."
)

# Revenue table — wrong alignment
p = doc.add_paragraph(
    "GENERAL FUND REVENUES (FY 2024-2025 Budget):\n"
    "Property Tax: $62,340,000 (48.9%)\n"
    "Sales Tax: $28,410,000 (22.3%)\n"
    "Income Tax: $18,750,000 (14.7%)\n"
    "Intergovernmental: $9,200,000 (7.2%)\n"
    "Other Revenue: $8,750,000 (6.9%)\n"
    "TOTAL: $127,450,000 (100.0%)"
)
p.alignment = WD_ALIGN_PARAGRAPH.RIGHT  # WRONG

# CREDIT RATINGS — no heading style
p = doc.add_paragraph("CREDIT RATINGS")
p.runs[0].bold = True

# ERROR 4: Wrong S&P rating (AA- instead of AA)
doc.add_paragraph(
    "The Bonds have been rated 'AA-' by S&P Global Ratings and 'Aa2' by Moody's Investors "
    "Service. The City's underlying general obligation credit rating is 'AA-' from S&P "
    "and 'Aa2' from Moody's."
)

# TAX EXEMPTION
doc.add_heading("TAX EXEMPTION", level=1)
doc.add_paragraph(
    "In the opinion of Bond Counsel, under existing statutes, regulations, rulings, and "
    "court decisions, and assuming the accuracy of certain representations and compliance "
    "with certain covenants, interest on the Bonds is excludable from gross income for "
    "federal income tax purposes and is not an item of tax preference for purposes of "
    "the federal alternative minimum tax."
)

# CONTINUING DISCLOSURE — italic (wrong)
p = doc.add_paragraph(
    "CONTINUING DISCLOSURE UNDERTAKING\n"
    "The City has covenanted for the benefit of the holders and beneficial owners of the "
    "Bonds to provide certain financial information and operating data relating to the "
    "City by not later than 270 days after the end of the City's fiscal year, and to "
    "provide notices of the occurrence of certain events. The City has never failed to "
    "comply in all material respects with any previous continuing disclosure undertaking "
    "under Rule 15c2-12."
)
for run in p.runs:
    run.italic = True  # WRONG

# ERROR 5: Missing MSRB-required risk factors section
# (The document should have a "BONDHOLDERS' RISKS" or "RISK FACTORS" section
# that is required under MSRB disclosure guidelines, but it's absent)

# LEGAL MATTERS
doc.add_heading("LEGAL MATTERS", level=1)
doc.add_paragraph(
    "Legal matters incident to the authorization, issuance, sale, and delivery of the "
    "Bonds are subject to the approving legal opinion of Chapman & Cutler LLP, Bond "
    "Counsel. The proposed form of the opinion of Bond Counsel is included in Appendix C."
)

# UNDERWRITING — centered (wrong)
p = doc.add_paragraph("UNDERWRITING")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.runs[0].bold = True

doc.add_paragraph(
    "The Bonds are being purchased by Stifel, Nicolaus & Company, Incorporated (the "
    "'Underwriter'). The Underwriter has agreed, subject to certain conditions, to "
    "purchase the Bonds at a price of $45,675,000 (representing the par amount of "
    "$45,000,000 plus original issue premium of $675,000)."
)

# APPENDICES reference — no structure
doc.add_paragraph(
    "APPENDIX A - Financial Statements of the City\n"
    "APPENDIX B - Form of Legal Opinion\n"
    "APPENDIX C - Form of Continuing Disclosure Undertaking\n"
    "APPENDIX D - Book-Entry Only System"
)

doc.save("/home/ga/Documents/os_draft_greenfield.docx")
print("Draft Official Statement created")
PYEOF

sudo chown ga:ga /home/ga/Documents/os_draft_greenfield.docx
sudo chmod 666 /home/ga/Documents/os_draft_greenfield.docx

date +%s > /tmp/municipal_bond_official_statement_start_ts

echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORMTHEME=gtk2 wps /home/ga/Documents/os_draft_greenfield.docx > /tmp/wps_task.log 2>&1 &"

if ! wait_for_process "wps" 20; then
    echo "ERROR: WPS Writer failed to start"
    cat /tmp/wps_task.log
fi

echo "Waiting for WPS window..."
sleep 5

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

    if wmctrl -l | grep -qi "os_draft\|Writer" && ! wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        echo "Document window is visible!"
        document_visible=true
    else
        echo "Document window not yet visible, waiting..."
        sleep 2
    fi
done

if ! wait_for_window "WPS Writer\|os_draft\|Writer" 20; then
    echo "Warning: WPS window not detected"
    wmctrl -l
fi

sleep 5

wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 1
fi

check_document_open() {
    local win_list=$(wmctrl -l 2>/dev/null)
    if echo "$win_list" | grep -qi "os_draft"; then return 0; fi
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
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/os_draft_greenfield.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
    if check_document_open; then
        document_opened=true
        break
    fi
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/os_draft_greenfield.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
done

sleep 3
DISPLAY=:1 xdotool key ctrl+Home
sleep 1

for i in 1 2 3; do
    DISPLAY=:1 wmctrl -c "System Check" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done
sleep 1

take_screenshot /tmp/municipal_bond_official_statement_start_screenshot.png

echo "=== Municipal Bond Official Statement Task Setup Complete ==="
