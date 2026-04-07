#!/bin/bash
echo "=== Setting up dcf_valuation_model task ==="

# --- Source shared utilities ---
source /workspace/scripts/task_utils.sh

# --- Clean stale outputs BEFORE recording timestamp ---
rm -f /home/ga/Documents/Spreadsheets/novapeak_dcf_model.xlsx
rm -f /tmp/dcf_valuation_model_result.json
cleanup_temp_files
kill_onlyoffice ga
sleep 1

# --- Record anti-gaming timestamp ---
echo $(date +%s) > /tmp/dcf_valuation_model_start_ts

# --- Create data directory ---
mkdir -p /home/ga/Documents/Spreadsheets
chown -R ga:ga /home/ga/Documents

# --- Generate historical financials workbook ---
cat > /tmp/create_novapeak_historicals.py << 'PYEOF'
#!/usr/bin/env python3
"""Generate NovaPeak Analytics historical financials workbook."""
import sys
import openpyxl
from openpyxl.styles import Font, Alignment, numbers, PatternFill, Border, Side

output_path = sys.argv[1]
wb = openpyxl.Workbook()

# ---------- Styling ----------
header_font = Font(name='Calibri', size=11, bold=True)
title_font = Font(name='Calibri', size=13, bold=True, color='1F4E79')
number_font = Font(name='Calibri', size=11)
italic_font = Font(name='Calibri', size=11, italic=True)
currency_fmt = '#,##0'
pct_fmt = '0.0%'
header_fill = PatternFill(start_color='D6E4F0', end_color='D6E4F0', fill_type='solid')
subtotal_fill = PatternFill(start_color='E2EFDA', end_color='E2EFDA', fill_type='solid')
thin_border = Border(
    bottom=Side(style='thin', color='B4C6E7')
)

def write_row(ws, row, label, values, is_header=False, is_subtotal=False,
              is_negative=False, indent=0, is_italic=False):
    """Write a labeled row with Year 1-3 values."""
    cell = ws.cell(row=row, column=1, value=('  ' * indent) + label)
    if is_header:
        cell.font = header_font
    elif is_italic:
        cell.font = italic_font
    else:
        cell.font = number_font

    for i, val in enumerate(values):
        c = ws.cell(row=row, column=2 + i)
        if val is None or val == '':
            c.value = None
        elif isinstance(val, str):
            c.value = val
            c.font = number_font
        else:
            c.value = val
            c.number_format = currency_fmt
            c.font = number_font
            c.alignment = Alignment(horizontal='right')

    if is_subtotal:
        for col in range(1, 5):
            ws.cell(row=row, column=col).fill = subtotal_fill
            ws.cell(row=row, column=col).font = header_font
    if is_header:
        for col in range(1, 5):
            ws.cell(row=row, column=col).border = thin_border

# ================================================================
# SHEET 1: Historical Income Statement
# ================================================================
ws_is = wb.active
ws_is.title = 'Historical_IS'
ws_is.sheet_properties.tabColor = '1F4E79'

# Column widths
ws_is.column_dimensions['A'].width = 38
ws_is.column_dimensions['B'].width = 18
ws_is.column_dimensions['C'].width = 18
ws_is.column_dimensions['D'].width = 18

# Title
ws_is.cell(row=1, column=1, value='NovaPeak Analytics - Income Statement').font = title_font

# Column headers
for col, label in enumerate(['', 'Year 1', 'Year 2', 'Year 3'], 1):
    c = ws_is.cell(row=3, column=col, value=label)
    c.font = header_font
    c.fill = header_fill
    c.alignment = Alignment(horizontal='center')

# ----- Income Statement Data -----
# Revenue
# Y1: $4,200,000  Y2: $5,880,000 (+40%)  Y3: $7,644,000 (+30%)
write_row(ws_is, 5, 'Revenue', [4200000, 5880000, 7644000], is_subtotal=True)

# COGS: Y1 30%, Y2 30%, Y3 29%
write_row(ws_is, 6, 'Cost of Goods Sold', [-1260000, -1764000, -2216760], indent=1)

# Gross Profit
write_row(ws_is, 7, 'Gross Profit', [2940000, 4116000, 5427240], is_subtotal=True)

# Blank separator
write_row(ws_is, 8, '', [None, None, None])

# Operating Expenses header
write_row(ws_is, 9, 'Operating Expenses', [None, None, None], is_header=True)

# S&M: Y1 25%, Y2 24%, Y3 23%
write_row(ws_is, 10, 'Sales & Marketing', [-1050000, -1411200, -1758120], indent=1)

# R&D: Y1 20%, Y2 18%, Y3 17%
write_row(ws_is, 11, 'Research & Development', [-840000, -1058400, -1299480], indent=1)

# G&A: Y1 12%, Y2 10%, Y3 8.5%
write_row(ws_is, 12, 'General & Administrative', [-504000, -588000, -649740], indent=1)

# Restructuring (one-time)
write_row(ws_is, 13, 'Restructuring Charge (one-time)', [0, -500000, 0],
          indent=1, is_italic=True)

# Total Operating Expenses
write_row(ws_is, 14, 'Total Operating Expenses',
          [-2394000, -3557600, -3707340], is_subtotal=True)

# Blank
write_row(ws_is, 15, '', [None, None, None])

# EBITDA: Gross Profit - Total OpEx (absolute values)
write_row(ws_is, 16, 'EBITDA', [546000, 558400, 1719900], is_subtotal=True)

# D&A: Y1 5%, Y2 4.5%, Y3 4%
write_row(ws_is, 17, 'Depreciation & Amortization', [-210000, -264600, -305760], indent=1)

# EBIT
write_row(ws_is, 18, 'EBIT (Operating Income)', [336000, 293800, 1414140], is_subtotal=True)

# Interest
write_row(ws_is, 19, 'Interest Expense', [-80000, -80000, -80000], indent=1)

# EBT
write_row(ws_is, 20, 'Earnings Before Tax', [256000, 213800, 1334140])

# Tax
write_row(ws_is, 21, 'Income Tax (25%)', [-64000, -53450, -333535], indent=1)

# Net Income
write_row(ws_is, 22, 'Net Income', [192000, 160350, 1000605], is_subtotal=True)

# ================================================================
# SHEET 2: Historical Balance Sheet
# ================================================================
ws_bs = wb.create_sheet('Historical_BS')
ws_bs.sheet_properties.tabColor = '548235'

# Column widths
ws_bs.column_dimensions['A'].width = 38
ws_bs.column_dimensions['B'].width = 18
ws_bs.column_dimensions['C'].width = 18
ws_bs.column_dimensions['D'].width = 18

# Title
ws_bs.cell(row=1, column=1,
           value='NovaPeak Analytics - Balance Sheet').font = title_font

# Column headers
for col, label in enumerate(['', 'Year 1', 'Year 2', 'Year 3'], 1):
    c = ws_bs.cell(row=3, column=col, value=label)
    c.font = header_font
    c.fill = header_fill
    c.alignment = Alignment(horizontal='center')

# ----- Assets -----
write_row(ws_bs, 5, 'ASSETS', [None, None, None], is_header=True)

write_row(ws_bs, 6, 'Cash & Cash Equivalents',
          [1200000, 1500000, 2200000], indent=1)

# AR: 15% of revenue consistently
write_row(ws_bs, 7, 'Accounts Receivable',
          [630000, 882000, 1146600], indent=1)

# Prepaid: 4% of revenue
write_row(ws_bs, 8, 'Prepaid Expenses & Other',
          [168000, 235200, 305760], indent=1)

write_row(ws_bs, 9, 'Total Current Assets',
          [1998000, 2617200, 3652360], is_subtotal=True)

# PP&E (net)
write_row(ws_bs, 10, 'Property, Plant & Equipment (net)',
          [840000, 1058400, 1223040], indent=1)

write_row(ws_bs, 11, 'Intangible Assets',
          [420000, 420000, 420000], indent=1)

write_row(ws_bs, 12, 'Total Assets',
          [3258000, 4095600, 5295400], is_subtotal=True)

# Blank
write_row(ws_bs, 13, '', [None, None, None])

# ----- Liabilities -----
write_row(ws_bs, 14, 'LIABILITIES & EQUITY', [None, None, None], is_header=True)

# AP: 30% of COGS
write_row(ws_bs, 15, 'Accounts Payable',
          [378000, 529200, 665028], indent=1)

# Accrued: 6% of revenue
write_row(ws_bs, 16, 'Accrued Expenses',
          [252000, 352800, 458640], indent=1)

# Deferred Revenue: 3% of revenue
write_row(ws_bs, 17, 'Deferred Revenue',
          [126000, 176400, 229320], indent=1)

write_row(ws_bs, 18, 'Total Current Liabilities',
          [756000, 1058400, 1352988], is_subtotal=True)

write_row(ws_bs, 19, 'Long-term Debt',
          [1000000, 1000000, 1000000], indent=1)

write_row(ws_bs, 20, 'Total Liabilities',
          [1756000, 2058400, 2352988], is_subtotal=True)

# Equity (plug to balance)
write_row(ws_bs, 21, '', [None, None, None])
write_row(ws_bs, 22, "Shareholders' Equity",
          [1502000, 2037200, 2942412], is_subtotal=True)

write_row(ws_bs, 23, 'Total Liabilities & Equity',
          [3258000, 4095600, 5295400], is_subtotal=True)

# ================================================================
# Save
# ================================================================
wb.save(output_path)
print(f"Created workbook at {output_path}")
PYEOF

chmod +x /tmp/create_novapeak_historicals.py

HIST_PATH="/home/ga/Documents/Spreadsheets/novapeak_historicals.xlsx"
python3 /tmp/create_novapeak_historicals.py "$HIST_PATH"
chown ga:ga "$HIST_PATH"

echo "Historical workbook created at $HIST_PATH"
ls -la "$HIST_PATH"

# --- Launch ONLYOFFICE with the file ---
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$HIST_PATH' > /tmp/onlyoffice_dcf.log 2>&1 &"

wait_for_process "onlyoffice-desktopeditors" 20
wait_for_window "ONLYOFFICE" 30
protect_onlyoffice_from_oom

# Focus and maximize
sleep 3
focus_onlyoffice_window

# Click to ensure focus
DISPLAY=:1 xdotool mousemove 600 400 click 1
sleep 1

# Take initial screenshot
scrot /tmp/dcf_valuation_model_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/dcf_valuation_model_initial.png 2>/dev/null || true

echo "=== dcf_valuation_model task setup complete ==="
