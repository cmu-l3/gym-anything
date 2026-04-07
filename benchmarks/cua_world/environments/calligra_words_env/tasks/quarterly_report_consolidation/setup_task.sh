#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Quarterly Report Consolidation Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

kill_calligra_processes
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any existing target document
rm -f /home/ga/Documents/quarterly_review_q3.odt

# ------------------------------------------------------------------
# Generate the three distinct source files using odfpy
# Each has intentionally different formatting to test unification
# ------------------------------------------------------------------
cat << 'PYEOF' > /tmp/generate_sources.py
import os
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import P
from odf.table import Table, TableRow, TableCell

def add_table(doc, rows_data):
    table = Table()
    for row_data in rows_data:
        tr = TableRow()
        for cell_data in row_data:
            tc = TableCell()
            tc.addElement(P(text=str(cell_data)))
            tr.addElement(tc)
        table.addElement(tr)
    doc.text.addElement(table)

# --- 1. Sales Report ---
doc_s = OpenDocumentText()
s_p = Style(name="SalesPara", family="paragraph")
s_p.addElement(ParagraphProperties(textalign="left"))
s_p.addElement(TextProperties(fontname="Arial", fontsize="11pt"))
doc_s.automaticstyles.addElement(s_p)

s_h = Style(name="SalesHeading", family="paragraph")
s_h.addElement(TextProperties(fontname="Arial", fontsize="14pt", fontweight="bold"))
doc_s.automaticstyles.addElement(s_h)

doc_s.text.addElement(P(stylename=s_h, text="Sales"))
doc_s.text.addElement(P(stylename=s_h, text="Revenue Performance"))
doc_s.text.addElement(P(stylename=s_p, text="Q3 revenue reached $47.3M, driven by strong enterprise renewals."))
doc_s.text.addElement(P(stylename=s_h, text="Regional Breakdown"))
doc_s.text.addElement(P(stylename=s_p, text="The Northeast region outperformed expectations, while the West region saw a slight dip."))
add_table(doc_s, [["Region", "Q3 Actual", "Variance"], ["Northeast", "$15.2M", "+5%"], ["West", "$12.1M", "-2%"]])
doc_s.text.addElement(P(stylename=s_h, text="Customer Acquisition"))
doc_s.text.addElement(P(stylename=s_p, text="We closed 847 new enterprise accounts this quarter."))
doc_s.text.addElement(P(stylename=s_h, text="Pipeline Outlook"))
doc_s.text.addElement(P(stylename=s_p, text="Current pipeline value stands at $62M for the upcoming quarter."))
doc_s.save("/home/ga/Documents/sales_q3.odt")

# --- 2. Operations Report ---
doc_o = OpenDocumentText()
o_p = Style(name="OpsPara", family="paragraph")
o_p.addElement(ParagraphProperties(textalign="justify"))
o_p.addElement(TextProperties(fontname="Times New Roman", fontsize="12pt"))
doc_o.automaticstyles.addElement(o_p)

o_h = Style(name="OpsHeading", family="paragraph")
o_h.addElement(TextProperties(fontname="Times New Roman", fontsize="13pt", fontstyle="italic"))
doc_o.automaticstyles.addElement(o_h)

doc_o.text.addElement(P(stylename=o_h, text="Operations"))
doc_o.text.addElement(P(stylename=o_h, text="Production Output"))
doc_o.text.addElement(P(stylename=o_p, text="We produced 142,000 units in Q3, representing a 5% increase over Q2."))
doc_o.text.addElement(P(stylename=o_h, text="Quality Metrics"))
doc_o.text.addElement(P(stylename=o_p, text="Our overall defect rate dropped to 0.8%, achieving our annual target early."))
add_table(doc_o, [["Metric", "Target", "Actual"], ["On-time Delivery", "98%", "99.2%"], ["Equipment Uptime", "95%", "96.5%"]])
doc_o.text.addElement(P(stylename=o_h, text="Facility Utilization"))
doc_o.text.addElement(P(stylename=o_p, text="The new Memphis distribution center is fully operational and at 85% capacity."))
doc_o.save("/home/ga/Documents/operations_q3.odt")

# --- 3. Finance Report ---
doc_f = OpenDocumentText()
f_p = Style(name="FinPara", family="paragraph")
f_p.addElement(ParagraphProperties(textalign="left"))
f_p.addElement(TextProperties(fontname="Liberation Sans", fontsize="11pt"))
doc_f.automaticstyles.addElement(f_p)

f_h = Style(name="FinHeading", family="paragraph")
f_h.addElement(TextProperties(fontname="Liberation Sans", fontsize="12pt", textunderlinestyle="solid"))
doc_f.automaticstyles.addElement(f_h)

doc_f.text.addElement(P(stylename=f_h, text="Finance"))
doc_f.text.addElement(P(stylename=f_h, text="Income Statement Summary"))
doc_f.text.addElement(P(stylename=f_p, text="Net income for the quarter was $8.7M with an EBITDA of $14.2M."))
doc_f.text.addElement(P(stylename=f_h, text="Budget Variance Analysis"))
doc_f.text.addElement(P(stylename=f_p, text="Operating expenses were 2.1% below budget due to reduced travel costs."))
add_table(doc_f, [["Line Item", "Budget", "Actual", "Variance"], ["Revenue", "$46.0M", "$47.3M", "+$1.3M"], ["EBITDA", "$13.5M", "$14.2M", "+$0.7M"]])
doc_f.text.addElement(P(stylename=f_h, text="Cash Flow"))
doc_f.text.addElement(P(stylename=f_p, text="Ending cash position remains strong at $31.4M."))
doc_f.text.addElement(P(stylename=f_h, text="Capital Expenditures"))
doc_f.text.addElement(P(stylename=f_p, text="CapEx was $4.2M, primarily driven by the Memphis facility equipment."))
doc_f.save("/home/ga/Documents/finance_q3.odt")
PYEOF

python3 /tmp/generate_sources.py
chown ga:ga /home/ga/Documents/*_q3.odt

# Start Calligra Words with a blank document so the agent starts fresh
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords >/tmp/calligra_words_task.log 2>&1 < /dev/null &"
sleep 5

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="