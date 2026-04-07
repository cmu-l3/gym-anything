#!/bin/bash
# Note: no set -euo pipefail — commands need to be fault-tolerant

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp
rm -f /tmp/loan_risk_result.json

# Ensure Documents directory exists
su - ga -c "mkdir -p /home/ga/Documents"

# Create the partial spreadsheet using Python + openpyxl
python3 -c "import openpyxl" 2>/dev/null || pip3 install -q openpyxl

python3 << 'PYEOF'
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

wb = openpyxl.Workbook()

# ============================================================
# Sheet 1: Loan Portfolio
# ============================================================
ws = wb.active
ws.title = "Loan Portfolio"

# Headers
headers = [
    "LoanID", "LoanAmount", "AnnualRate", "TermMonths",
    "CreditScore", "DTI_Ratio", "LTV_Ratio", "BorrowerName",
    "MonthlyPayment", "RiskScore", "RiskCategory", "ExpectedLoss"
]
header_fill = PatternFill(start_color="1F4E79", end_color="1F4E79", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF")

for col, h in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col, value=h)
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal="center")

# Loan data: LoanID, LoanAmount, AnnualRate, TermMonths, CreditScore, DTI, LTV, BorrowerName
loans = [
    ("L001", 185000, 0.0675, 360, 720, 0.28, 0.78, "Maria Santos"),
    ("L002", 320000, 0.0750, 360, 680, 0.38, 0.85, "John Patterson"),
    ("L003",  95000, 0.0595, 180, 760, 0.22, 0.65, "David Kim"),
    ("L004", 450000, 0.0825, 360, 630, 0.42, 0.92, "Rachel Torres"),
    ("L005", 125000, 0.0625, 240, 745, 0.30, 0.70, "Michael Chang"),
    ("L006", 275000, 0.0700, 360, 695, 0.35, 0.82, "Angela Williams"),
    ("L007",  55000, 0.0550, 120, 800, 0.18, 0.55, "Robert Olsen"),
    ("L008", 390000, 0.0800, 360, 645, 0.44, 0.88, "Jennifer Martinez"),
    ("L009", 165000, 0.0650, 300, 730, 0.32, 0.72, "Carlos Rodriguez"),
    ("L010", 220000, 0.0725, 360, 705, 0.36, 0.80, "Susan Lee"),
    ("L011", 480000, 0.0850, 360, 615, 0.46, 0.95, "Thomas Brown"),
    ("L012",  78000, 0.0575, 180, 785, 0.24, 0.60, "Linda Wilson"),
    ("L013", 310000, 0.0775, 360, 660, 0.40, 0.86, "James Garcia"),
    ("L014", 145000, 0.0625, 240, 755, 0.27, 0.68, "Patricia Nelson"),
    ("L015", 265000, 0.0700, 360, 690, 0.37, 0.81, "Kevin Anderson"),
    ("L016",  88000, 0.0560, 120, 810, 0.20, 0.52, "Dorothy Thompson"),
    ("L017", 425000, 0.0825, 360, 625, 0.45, 0.91, "Mark Jackson"),
    ("L018", 195000, 0.0660, 360, 725, 0.31, 0.75, "Christine White"),
    ("L019", 340000, 0.0775, 360, 665, 0.41, 0.87, "Steven Harris"),
    ("L020", 115000, 0.0590, 180, 770, 0.26, 0.62, "Barbara Davis"),
]

for r, loan in enumerate(loans, 2):
    for c, val in enumerate(loan, 1):
        ws.cell(row=r, column=c, value=val)
    # Columns I, J, K, L (MonthlyPayment, RiskScore, RiskCategory, ExpectedLoss) = empty
    # Add placeholder comments
    ws.cell(row=r, column=9, value=None)   # MonthlyPayment — use PMT formula
    ws.cell(row=r, column=10, value=None)  # RiskScore
    ws.cell(row=r, column=11, value=None)  # RiskCategory
    ws.cell(row=r, column=12, value=None)  # ExpectedLoss

# Instruction row at top
ws.insert_rows(1)
ws["A1"] = "INCOMPLETE — Fill in columns I (MonthlyPayment), J (RiskScore), K (RiskCategory), L (ExpectedLoss) using Risk Parameters sheet"
ws["A1"].font = Font(bold=True, color="FF0000", size=11)
ws.merge_cells("A1:L1")

# Column widths
for col, width in zip("ABCDEFGHIJKL", [8,12,12,12,12,10,10,20,15,10,14,14]):
    ws.column_dimensions[col].width = width

# ============================================================
# Sheet 2: Risk Parameters
# ============================================================
ws2 = wb.create_sheet("Risk Parameters")

ws2["A1"] = "CREDIT SCORE COMPONENT"
ws2["A1"].font = Font(bold=True, size=12)
ws2["A2"] = "Credit Score Range"
ws2["B2"] = "Score Threshold (<=)"
ws2["C2"] = "Risk Component Value"
credit_data = [
    ("750 and above",   999, 1.0),
    ("700 - 749",       749, 1.5),
    ("650 - 699",       699, 2.5),
    ("600 - 649",       649, 3.5),
    ("Below 600",       599, 5.0),
]
for r, (label, threshold, val) in enumerate(credit_data, 3):
    ws2.cell(row=r, column=1, value=label)
    ws2.cell(row=r, column=2, value=threshold)
    ws2.cell(row=r, column=3, value=val)

ws2["A9"] = "DTI RATIO COMPONENT"
ws2["A9"].font = Font(bold=True, size=12)
ws2["A10"] = "DTI Ratio Range"
ws2["B10"] = "DTI Threshold (<=)"
ws2["C10"] = "Risk Component Value"
dti_data = [
    ("Below 0.30",   0.299, 1.0),
    ("0.30 - 0.35",  0.350, 2.0),
    ("0.35 - 0.40",  0.400, 3.0),
    ("Above 0.40",   9.999, 4.5),
]
for r, (label, threshold, val) in enumerate(dti_data, 11):
    ws2.cell(row=r, column=1, value=label)
    ws2.cell(row=r, column=2, value=threshold)
    ws2.cell(row=r, column=3, value=val)

ws2["A16"] = "LTV RATIO COMPONENT"
ws2["A16"].font = Font(bold=True, size=12)
ws2["A17"] = "LTV Ratio Range"
ws2["B17"] = "LTV Threshold (<=)"
ws2["C17"] = "Risk Component Value"
ltv_data = [
    ("Below 0.70",   0.699, 1.0),
    ("0.70 - 0.80",  0.800, 1.5),
    ("0.80 - 0.90",  0.900, 2.5),
    ("Above 0.90",   9.999, 4.0),
]
for r, (label, threshold, val) in enumerate(ltv_data, 18):
    ws2.cell(row=r, column=1, value=label)
    ws2.cell(row=r, column=2, value=threshold)
    ws2.cell(row=r, column=3, value=val)

ws2["A23"] = "RISK CATEGORY THRESHOLDS"
ws2["A23"].font = Font(bold=True, size=12)
ws2["A24"] = "Total Risk Score Range"
ws2["B24"] = "Category"
ws2["C24"] = "Default Rate"
category_data = [
    ("3.0 - 4.5",  "Low Risk",      0.005),
    ("4.5 - 7.0",  "Moderate Risk", 0.020),
    ("7.0 - 9.5",  "High Risk",     0.050),
    ("Above 9.5",  "Critical Risk", 0.100),
]
for r, (rng, cat, rate) in enumerate(category_data, 25):
    ws2.cell(row=r, column=1, value=rng)
    ws2.cell(row=r, column=2, value=cat)
    ws2.cell(row=r, column=3, value=rate)

# ============================================================
# Sheet 3: Portfolio Summary
# ============================================================
ws3 = wb.create_sheet("Portfolio Summary")
ws3["A1"] = "LOAN PORTFOLIO SUMMARY DASHBOARD"
ws3["A1"].font = Font(bold=True, size=14)

summary_labels = [
    ("A3", "Total Portfolio Value ($):"),
    ("A4", "Average Loan Amount ($):"),
    ("A5", "Average Annual Interest Rate:"),
    ("A6", "Total Monthly Payment Obligation ($):"),
    ("A7", "Average Credit Score:"),
    ("A8", "Number of Low Risk Loans:"),
    ("A9", "Number of Moderate Risk Loans:"),
    ("A10", "Number of High Risk Loans:"),
    ("A11", "Number of Critical Risk Loans:"),
    ("A12", "Total Expected Loss ($):"),
    ("A13", "Portfolio Expected Loss Rate:"),
]
for cell_ref, label in summary_labels:
    ws3[cell_ref] = label
    ws3[cell_ref].font = Font(bold=True)

# Column B is empty — agent must fill in formulas referencing Loan Portfolio sheet
for row in range(3, 14):
    ws3.cell(row=row, column=2, value=None)

ws3["A15"] = "NOTE: Use cross-sheet references to 'Loan Portfolio' sheet to populate column B"
ws3["A15"].font = Font(italic=True, color="808080")

wb.save("/home/ga/Documents/loan_portfolio_partial.xlsx")
print("Partial spreadsheet created: /home/ga/Documents/loan_portfolio_partial.xlsx")
print(f"  {len(loans)} loans loaded, 4 formula columns empty")
PYEOF

# Fix ownership so LibreOffice (running as ga) can edit the file
chown ga:ga /home/ga/Documents/loan_portfolio_partial.xlsx 2>/dev/null || true

# Record baseline
date +%s > /tmp/task_start_timestamp
echo "" > /tmp/loan_risk_result_placeholder

# Launch LibreOffice Calc
kill_calc 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/loan_portfolio_partial.xlsx > /tmp/calc.log 2>&1 &"
sleep 8

WID=$(get_calc_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot "/tmp/loan_risk_start.png" || true

echo "=== Setup complete ==="
echo "File: /home/ga/Documents/loan_portfolio_partial.xlsx"
echo "Task: Complete PMT formulas, risk scoring, categories, expected loss, and summary"
