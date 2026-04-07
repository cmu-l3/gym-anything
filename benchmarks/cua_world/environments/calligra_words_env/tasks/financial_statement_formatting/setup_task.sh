#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Financial Statement Formatting Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/novatech_financials.odt
rm -f /home/ga/Desktop/financial_formatting_spec.txt

# ------------------------------------------------------------------
# Create the formatting specification text file
# ------------------------------------------------------------------
cat << 'EOF' > /home/ga/Desktop/financial_formatting_spec.txt
NovaTech Solutions Financial Formatting Specification (US GAAP Presentation)

1. Document Title
   - Text: "NOVATECH SOLUTIONS INC. 2025 FINANCIAL REPORT"
   - Alignment: Centered
   - Style: Bold, 16pt font size or larger

2. Section Headings
   - The 4 main section headings ("Independent Auditor's Report", "Balance Sheet", "Income Statement", "Statement of Cash Flows") must be formatted using the standard "Heading 1" style.

3. Auditor's Report Narrative
   - The body text paragraph of the auditor's report must be Justified.

4. Pagination
   - Each of the three financial statements MUST begin on a new page. Insert page breaks before the headings for the Balance Sheet, Income Statement, and Statement of Cash Flows.

5. Financial Tables Formatting
   - Table Header Rows (top row): Centered and Bold.
   - Numerical Data (Columns 2 and 3): Right-aligned.
   - Account Labels (Column 1): Left-aligned.
   - Total Rows Emphasis: The text must be Bold for the following specific rows: "Total Assets", "Total Liabilities and Equity", "Gross Profit", "Net Income", and "Net Cash Provided by Operating Activities".
EOF
chown ga:ga /home/ga/Desktop/financial_formatting_spec.txt

# ------------------------------------------------------------------
# Create the unformatted Financial Report using odfpy
# Contains unformatted paragraphs and tables
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P
from odf.table import Table, TableColumn, TableRow, TableCell

doc = OpenDocumentText()

def add_p(text):
    doc.text.addElement(P(text=text))

add_p("NOVATECH SOLUTIONS INC. 2025 FINANCIAL REPORT")
add_p("")
add_p("Independent Auditor's Report")
add_p("We have audited the accompanying financial statements of NovaTech Solutions Inc., which comprise the balance sheet as of December 31, 2025, and the related statements of income, and cash flows for the year then ended. In our opinion, the accompanying financial statements present fairly, in all material respects, the financial position of NovaTech Solutions Inc. as of December 31, 2025, and the results of its operations and its cash flows for the year then ended in accordance with accounting principles generally accepted in the United States of America.")
add_p("")

def make_table(title, rows):
    add_p(title)
    tbl = Table()
    for r in rows:
        tr = TableRow()
        for c in r:
            tc = TableCell()
            tc.addElement(P(text=str(c)))
            tr.addElement(tc)
        tbl.addElement(tr)
    doc.text.addElement(tbl)
    add_p("")

make_table("Balance Sheet", [
    ["Account", "2025 ($)", "2024 ($)"],
    ["Cash and Cash Equivalents", "4,520,100", "3,100,500"],
    ["Accounts Receivable", "1,250,000", "1,100,000"],
    ["Inventory", "850,000", "920,000"],
    ["Total Assets", "6,620,100", "5,120,500"],
    ["Accounts Payable", "950,000", "820,000"],
    ["Long-Term Debt", "2,100,000", "2,500,000"],
    ["Total Liabilities and Equity", "6,620,100", "5,120,500"]
])

make_table("Income Statement", [
    ["Account", "2025 ($)", "2024 ($)"],
    ["Revenue", "12,400,000", "10,200,000"],
    ["Cost of Goods Sold", "4,800,000", "4,100,000"],
    ["Gross Profit", "7,600,000", "6,100,000"],
    ["Operating Expenses", "3,100,000", "2,800,000"],
    ["Net Income", "4,500,000", "3,300,000"]
])

make_table("Statement of Cash Flows", [
    ["Account", "2025 ($)", "2024 ($)"],
    ["Net Income", "4,500,000", "3,300,000"],
    ["Depreciation", "450,000", "400,000"],
    ["Changes in Working Capital", "(200,000)", "(150,000)"],
    ["Net Cash Provided by Operating Activities", "4,750,000", "3,550,000"]
])

doc.save("/home/ga/Documents/novatech_financials.odt")
PYEOF
chown ga:ga /home/ga/Documents/novatech_financials.odt

# Launch Calligra Words
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/novatech_financials.odt"
sleep 5

# Maximize and Focus window
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" || true
fi

# Take initial screenshot
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="