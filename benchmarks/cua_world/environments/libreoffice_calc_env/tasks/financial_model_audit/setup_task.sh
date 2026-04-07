#!/bin/bash
# Note: no set -euo pipefail — commands need to be fault-tolerant

source /workspace/scripts/task_utils.sh

echo "=== Setting up Financial Model Audit Task ==="

# Clean up stale outputs BEFORE recording timestamp
rm -f /tmp/financial_model_audit_result.json
rm -f /home/ga/Documents/corrected_financial_model.xlsx
rm -f /home/ga/Documents/corrected_financial_model.ods

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Documents directory exists
su - ga -c "mkdir -p /home/ga/Documents"

# Install openpyxl if not already installed
python3 -c "import openpyxl" 2>/dev/null || pip3 install -q openpyxl

# Create the financial model spreadsheet with deliberate errors
python3 << 'PYEOF'
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side, numbers

wb = openpyxl.Workbook()

# --- Style definitions ---
title_font = Font(bold=True, size=14)
section_font = Font(bold=True, size=11, color="FFFFFF")
section_fill = PatternFill(start_color="2F5496", end_color="2F5496", fill_type="solid")
header_font = Font(bold=True, size=10)
header_fill = PatternFill(start_color="D6E4F0", end_color="D6E4F0", fill_type="solid")
label_font = Font(size=10)
bold_font = Font(bold=True, size=10)
error_font = Font(bold=True, size=10, color="FF0000")
note_font = Font(italic=True, size=9, color="808080")
currency_fmt = '#,##0'
pct_fmt = '0.0%'
thin_border = Border(
    bottom=Side(style='thin', color='000000')
)

def style_section_header(ws, row, text, max_col=3):
    """Write a section header row with colored background."""
    cell = ws.cell(row=row, column=1, value=text)
    cell.font = section_font
    for c in range(1, max_col + 1):
        ws.cell(row=row, column=c).fill = section_fill
        ws.cell(row=row, column=c).font = section_font

def style_header_row(ws, row, labels):
    """Write column headers with light background."""
    for c, label in enumerate(labels, 1):
        cell = ws.cell(row=row, column=c, value=label)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center")

def write_label(ws, row, text, bold=False):
    """Write a label in column A."""
    cell = ws.cell(row=row, column=1, value=text)
    cell.font = bold_font if bold else label_font
    return cell

def write_value(ws, row, col, value, fmt=None, bold=False):
    """Write a numeric value with optional formatting."""
    cell = ws.cell(row=row, column=col, value=value)
    if fmt:
        cell.number_format = fmt
    if bold:
        cell.font = bold_font
    return cell

def write_formula(ws, row, col, formula, fmt=None, bold=False):
    """Write a formula with optional formatting."""
    cell = ws.cell(row=row, column=col)
    cell.value = formula
    if fmt:
        cell.number_format = fmt
    if bold:
        cell.font = bold_font
    return cell


# ============================================================
# SHEET 1: Income Statement
# ============================================================
ws_is = wb.active
ws_is.title = "Income Statement"

# Title
ws_is.cell(row=1, column=1, value="Income Statement").font = title_font
ws_is.merge_cells("A1:C1")

# Column headers
style_header_row(ws_is, 2, ["", "Q3 2024", "Q4 2024"])

# --- REVENUE ---
style_section_header(ws_is, 3, "REVENUE")

write_label(ws_is, 4, "Product Sales")
write_value(ws_is, 4, 2, 110000, currency_fmt)
write_value(ws_is, 4, 3, 125000, currency_fmt)

write_label(ws_is, 5, "Service Revenue")
write_value(ws_is, 5, 2, 32000, currency_fmt)
write_value(ws_is, 5, 3, 35000, currency_fmt)

write_label(ws_is, 6, "Total Revenue", bold=True)
write_formula(ws_is, 6, 2, "=SUM(B4:B5)", currency_fmt, bold=True)       # Q3: correct = 142,000
write_formula(ws_is, 6, 3, "=SUM(C4:C5)", currency_fmt, bold=True)       # Q4: correct = 160,000

# --- COST OF GOODS SOLD ---
style_section_header(ws_is, 8, "COST OF GOODS SOLD")

write_label(ws_is, 9, "Materials")
write_value(ws_is, 9, 2, 38000, currency_fmt)
write_value(ws_is, 9, 3, 42000, currency_fmt)

write_label(ws_is, 10, "Direct Labor")
write_value(ws_is, 10, 2, 25000, currency_fmt)
write_value(ws_is, 10, 3, 28000, currency_fmt)

write_label(ws_is, 11, "Shipping")
write_value(ws_is, 11, 2, 4800, currency_fmt)
write_value(ws_is, 11, 3, 5500, currency_fmt)

write_label(ws_is, 12, "Total COGS", bold=True)
write_formula(ws_is, 12, 2, "=SUM(B9:B11)", currency_fmt, bold=True)     # Q3: correct = 67,800
# ERROR #1: Q4 COGS double-counts Marketing (adds C19 which is an operating expense)
write_formula(ws_is, 12, 3, "=SUM(C9:C11)+C19", currency_fmt, bold=True) # Q4: WRONG = 84,000 (should be 75,500)

# --- GROSS PROFIT ---
write_label(ws_is, 14, "Gross Profit", bold=True)
write_formula(ws_is, 14, 2, "=B6-B12", currency_fmt, bold=True)          # Q3: correct = 74,200
write_formula(ws_is, 14, 3, "=C6-C12", currency_fmt, bold=True)          # Q4: cascades from Error #1

write_label(ws_is, 15, "Gross Margin %")
write_formula(ws_is, 15, 2, "=B14/B6", pct_fmt)                          # Q3: correct = 52.3%
# ERROR #2: Q4 Gross Margin references empty row 7 instead of Total Revenue row 6
write_formula(ws_is, 15, 3, "=C14/C7", pct_fmt)                          # Q4: WRONG — C7 is blank section header row

# --- OPERATING EXPENSES ---
style_section_header(ws_is, 17, "OPERATING EXPENSES")

write_label(ws_is, 18, "Rent")
write_value(ws_is, 18, 2, 4500, currency_fmt)
write_value(ws_is, 18, 3, 4500, currency_fmt)

write_label(ws_is, 19, "Marketing")
write_value(ws_is, 19, 2, 7500, currency_fmt)
write_value(ws_is, 19, 3, 8500, currency_fmt)

write_label(ws_is, 20, "Salaries")
write_value(ws_is, 20, 2, 30000, currency_fmt)
write_value(ws_is, 20, 3, 32000, currency_fmt)

write_label(ws_is, 21, "Utilities")
write_value(ws_is, 21, 2, 1100, currency_fmt)
write_value(ws_is, 21, 3, 1200, currency_fmt)

write_label(ws_is, 22, "Insurance")
write_value(ws_is, 22, 2, 2400, currency_fmt)
write_value(ws_is, 22, 3, 2400, currency_fmt)

write_label(ws_is, 23, "Depreciation")
write_value(ws_is, 23, 2, 3750, currency_fmt)
write_value(ws_is, 23, 3, 3750, currency_fmt)

write_label(ws_is, 24, "Total Operating Expenses", bold=True)
write_formula(ws_is, 24, 2, "=SUM(B18:B23)", currency_fmt, bold=True)    # Q3: correct = 49,250
# ERROR #3: Q4 OpEx SUM range stops at Utilities (row 21), misses Insurance and Depreciation
write_formula(ws_is, 24, 3, "=SUM(C18:C21)", currency_fmt, bold=True)    # Q4: WRONG = 46,200 (should be 52,350)

# --- OPERATING INCOME ---
write_label(ws_is, 26, "Operating Income", bold=True)
write_formula(ws_is, 26, 2, "=B14-B24", currency_fmt, bold=True)         # Q3: correct = 24,950
write_formula(ws_is, 26, 3, "=C14-C24", currency_fmt, bold=True)         # Q4: cascades

write_label(ws_is, 27, "Interest Expense")
write_value(ws_is, 27, 2, 1800, currency_fmt)
write_value(ws_is, 27, 3, 1650, currency_fmt)

write_label(ws_is, 28, "Income Before Tax", bold=True)
write_formula(ws_is, 28, 2, "=B26-B27", currency_fmt, bold=True)         # Q3: correct = 23,150
write_formula(ws_is, 28, 3, "=C26-C27", currency_fmt, bold=True)         # Q4: cascades

write_label(ws_is, 29, "Income Tax (25%)")
write_formula(ws_is, 29, 2, "=B28*0.25", currency_fmt)                   # Q3: correct = 5,787.50
# ERROR #4: Q4 Tax is hard-coded instead of formula
write_value(ws_is, 29, 3, 8750, currency_fmt)                            # Q4: WRONG — should be =C28*0.25

write_label(ws_is, 30, "Net Income", bold=True)
write_formula(ws_is, 30, 2, "=B28-B29", currency_fmt, bold=True)         # Q3: correct = 17,362.50
write_formula(ws_is, 30, 3, "=C28-C29", currency_fmt, bold=True)         # Q4: cascades from Error #4
# Add bottom border for emphasis
for col in range(1, 4):
    ws_is.cell(row=30, column=col).border = thin_border

# --- GROWTH ---
write_label(ws_is, 32, "QoQ Revenue Growth")
# ERROR #5: Uses subtraction instead of division — shows dollar change, not percentage
write_formula(ws_is, 32, 3, "=C6-B6", pct_fmt)                           # Q4: WRONG — shows 18,000 as %. Should be =(C6-B6)/B6

# Column widths
ws_is.column_dimensions['A'].width = 28
ws_is.column_dimensions['B'].width = 15
ws_is.column_dimensions['C'].width = 15


# ============================================================
# SHEET 2: Balance Sheet
# ============================================================
ws_bs = wb.create_sheet("Balance Sheet")

# Title
ws_bs.cell(row=1, column=1, value="Balance Sheet").font = title_font
ws_bs.merge_cells("A1:C1")

# Column headers
style_header_row(ws_bs, 2, ["", "Q3 2024", "Q4 2024"])

# --- ASSETS ---
style_section_header(ws_bs, 3, "ASSETS")

write_label(ws_bs, 4, "Cash")
write_value(ws_bs, 4, 2, 85000, currency_fmt)
write_value(ws_bs, 4, 3, 92725, currency_fmt)

write_label(ws_bs, 5, "Accounts Receivable")
write_value(ws_bs, 5, 2, 28000, currency_fmt)
write_value(ws_bs, 5, 3, 32000, currency_fmt)

write_label(ws_bs, 6, "Inventory")
write_value(ws_bs, 6, 2, 18500, currency_fmt)
write_value(ws_bs, 6, 3, 21000, currency_fmt)

write_label(ws_bs, 7, "Equipment")
write_value(ws_bs, 7, 2, 75000, currency_fmt)
write_value(ws_bs, 7, 3, 75000, currency_fmt)

write_label(ws_bs, 8, "Accumulated Depreciation")
write_value(ws_bs, 8, 2, -11250, currency_fmt)
write_value(ws_bs, 8, 3, -15000, currency_fmt)

write_label(ws_bs, 9, "Total Assets", bold=True)
write_formula(ws_bs, 9, 2, "=SUM(B4:B8)", currency_fmt, bold=True)       # Q3: 195,250
write_formula(ws_bs, 9, 3, "=SUM(C4:C8)", currency_fmt, bold=True)       # Q4: 205,725
for col in range(1, 4):
    ws_bs.cell(row=9, column=col).border = thin_border

# --- LIABILITIES ---
style_section_header(ws_bs, 11, "LIABILITIES")

write_label(ws_bs, 12, "Accounts Payable")
write_value(ws_bs, 12, 2, 15000, currency_fmt)
write_value(ws_bs, 12, 3, 18500, currency_fmt)

write_label(ws_bs, 13, "Short-term Debt")
write_value(ws_bs, 13, 2, 20000, currency_fmt)
write_value(ws_bs, 13, 3, 15000, currency_fmt)

write_label(ws_bs, 14, "Long-term Debt")
write_value(ws_bs, 14, 2, 45000, currency_fmt)
write_value(ws_bs, 14, 3, 45000, currency_fmt)

write_label(ws_bs, 15, "Total Liabilities", bold=True)
write_formula(ws_bs, 15, 2, "=SUM(B12:B14)", currency_fmt, bold=True)    # Q3: 80,000
write_formula(ws_bs, 15, 3, "=SUM(C12:C14)", currency_fmt, bold=True)    # Q4: 78,500
for col in range(1, 4):
    ws_bs.cell(row=15, column=col).border = thin_border

# --- EQUITY ---
style_section_header(ws_bs, 17, "EQUITY")

write_label(ws_bs, 18, "Common Stock")
write_value(ws_bs, 18, 2, 50000, currency_fmt)
write_value(ws_bs, 18, 3, 50000, currency_fmt)

write_label(ws_bs, 19, "Prior Retained Earnings")
write_value(ws_bs, 19, 2, 47887.50, currency_fmt)
write_value(ws_bs, 19, 3, 65250, currency_fmt)

write_label(ws_bs, 20, "Current Period Net Income")
write_formula(ws_bs, 20, 2, "='Income Statement'!B30", currency_fmt)     # Q3: correct ref to NI
# ERROR #6: Q4 references Operating Income (row 26) instead of Net Income (row 30)
write_formula(ws_bs, 20, 3, "='Income Statement'!C26", currency_fmt)     # Q4: WRONG — pulls Op Income

write_label(ws_bs, 21, "Dividends")
write_value(ws_bs, 21, 2, 0, currency_fmt)
write_value(ws_bs, 21, 3, -10900, currency_fmt)

write_label(ws_bs, 22, "Total Equity", bold=True)
write_formula(ws_bs, 22, 2, "=SUM(B18:B21)", currency_fmt, bold=True)    # Q3: 115,250
write_formula(ws_bs, 22, 3, "=SUM(C18:C21)", currency_fmt, bold=True)    # Q4: wrong due to Error #6
for col in range(1, 4):
    ws_bs.cell(row=22, column=col).border = thin_border

# --- BALANCE CHECK ---
write_label(ws_bs, 24, "Total Liabilities + Equity", bold=True)
write_formula(ws_bs, 24, 2, "=B15+B22", currency_fmt, bold=True)         # Q3: 195,250
write_formula(ws_bs, 24, 3, "=C15+C22", currency_fmt, bold=True)         # Q4: wrong due to Error #6

write_label(ws_bs, 26, "Balance Check", bold=True)
write_formula(ws_bs, 26, 2, '=IF(B9=B24,"OK","MISMATCH")')               # Q3: "OK"
write_formula(ws_bs, 26, 3, '=IF(C9=C24,"OK","MISMATCH")')               # Q4: "MISMATCH" — visible clue!
ws_bs.cell(row=26, column=3).font = error_font

# Column widths
ws_bs.column_dimensions['A'].width = 28
ws_bs.column_dimensions['B'].width = 15
ws_bs.column_dimensions['C'].width = 15


# ============================================================
# SHEET 3: Cash Flow Statement
# ============================================================
ws_cf = wb.create_sheet("Cash Flow Statement")

# Title
ws_cf.cell(row=1, column=1, value="Cash Flow Statement - Q4 2024").font = title_font
ws_cf.merge_cells("A1:B1")

# Column headers
style_header_row(ws_cf, 2, ["", "Q4 2024"])

# --- OPERATING ACTIVITIES ---
style_section_header(ws_cf, 3, "OPERATING ACTIVITIES", max_col=2)

write_label(ws_cf, 4, "Net Income")
# Correct cross-sheet reference to IS Net Income (but value will be wrong until IS errors are fixed)
write_formula(ws_cf, 4, 2, "='Income Statement'!C30", currency_fmt)

write_label(ws_cf, 5, "Add: Depreciation")
write_value(ws_cf, 5, 2, 3750, currency_fmt)

write_label(ws_cf, 6, "Change in Accounts Receivable")
write_value(ws_cf, 6, 2, -4000, currency_fmt)

write_label(ws_cf, 7, "Change in Inventory")
write_value(ws_cf, 7, 2, -2500, currency_fmt)

write_label(ws_cf, 8, "Change in Accounts Payable")
write_value(ws_cf, 8, 2, 3500, currency_fmt)

write_label(ws_cf, 9, "Operating Cash Flow", bold=True)
write_formula(ws_cf, 9, 2, "=SUM(B4:B8)", currency_fmt, bold=True)
for col in range(1, 3):
    ws_cf.cell(row=9, column=col).border = thin_border

# --- INVESTING ACTIVITIES ---
style_section_header(ws_cf, 11, "INVESTING ACTIVITIES", max_col=2)

write_label(ws_cf, 12, "Equipment Purchase")
write_value(ws_cf, 12, 2, 0, currency_fmt)

write_label(ws_cf, 13, "Investing Cash Flow", bold=True)
write_formula(ws_cf, 13, 2, "=B12", currency_fmt, bold=True)
for col in range(1, 3):
    ws_cf.cell(row=13, column=col).border = thin_border

# --- FINANCING ACTIVITIES ---
style_section_header(ws_cf, 15, "FINANCING ACTIVITIES", max_col=2)

write_label(ws_cf, 16, "Debt Repayment")
# ERROR #7: Wrong sign — should be -5000 (cash outflow) but entered as positive 5000
write_value(ws_cf, 16, 2, 5000, currency_fmt)                            # WRONG — should be -5000

write_label(ws_cf, 17, "Dividends Paid")
write_value(ws_cf, 17, 2, -10900, currency_fmt)

write_label(ws_cf, 18, "Financing Cash Flow", bold=True)
write_formula(ws_cf, 18, 2, "=SUM(B16:B17)", currency_fmt, bold=True)
for col in range(1, 3):
    ws_cf.cell(row=18, column=col).border = thin_border

# --- NET CASH CHANGE ---
write_label(ws_cf, 20, "Net Cash Change", bold=True)
write_formula(ws_cf, 20, 2, "=B9+B13+B18", currency_fmt, bold=True)
for col in range(1, 3):
    ws_cf.cell(row=20, column=col).border = thin_border

write_label(ws_cf, 22, "Beginning Cash")
write_value(ws_cf, 22, 2, 85000, currency_fmt)

write_label(ws_cf, 23, "Ending Cash", bold=True)
# ERROR #8: Hard-coded value instead of formula. Also doesn't match BS Cash (92,725)
write_value(ws_cf, 23, 2, 92500, currency_fmt)                           # WRONG — should be =B22+B20

# Column widths
ws_cf.column_dimensions['A'].width = 32
ws_cf.column_dimensions['B'].width = 15


# ============================================================
# Save workbook
# ============================================================
wb.save("/home/ga/Documents/financial_model.xlsx")
print("Financial model created: /home/ga/Documents/financial_model.xlsx")
print("  3 sheets: Income Statement, Balance Sheet, Cash Flow Statement")
print("  8 deliberate errors planted across all three sheets")
PYEOF

# Fix ownership so LibreOffice (running as ga) can edit the file
chown ga:ga /home/ga/Documents/financial_model.xlsx 2>/dev/null || true

# Launch LibreOffice Calc
kill_calc 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/financial_model.xlsx > /tmp/calc.log 2>&1 &"
sleep 8

WID=$(get_calc_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot "/tmp/financial_model_audit_start.png" || true

echo "=== Setup complete ==="
echo "File: /home/ga/Documents/financial_model.xlsx"
echo "Task: Audit and fix all errors in the three-sheet financial model"
