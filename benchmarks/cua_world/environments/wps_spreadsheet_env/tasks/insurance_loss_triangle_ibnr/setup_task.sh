#!/bin/bash
echo "=== Setting up insurance_loss_triangle_ibnr task ==="

INPUT_FILE="/home/ga/Documents/claims_data.xlsx"
OUTPUT_FILE="/home/ga/Documents/loss_reserve_analysis.xlsx"

# Delete stale outputs BEFORE recording timestamp
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f "$INPUT_FILE" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Generate realistic P&C insurance claims data with actuarial development patterns
python3 << 'PYEOF'
import random
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, numbers

random.seed(42)

wb = Workbook()

# ── Claims sheet ──────────────────────────────────────────────────────
ws_claims = wb.active
ws_claims.title = "Claims"

headers = ["ClaimID", "AccidentYear", "DevelopmentPeriod", "CumulativeIncurred"]
ws_claims.append(headers)

# Target triangle values (realistic P&C auto/property cumulative incurred)
# Pattern: ~5-8% growth per year, development factors decreasing from ~1.22 to ~1.01
triangle = {
    (2018, 12): 5230000, (2018, 24): 6380000, (2018, 36): 6850000,
    (2018, 48): 7020000, (2018, 60): 7110000, (2018, 72): 7180000,
    (2019, 12): 5890000, (2019, 24): 7150000, (2019, 36): 7680000,
    (2019, 48): 7870000, (2019, 60): 7960000,
    (2020, 12): 6410000, (2020, 24): 7820000, (2020, 36): 8400000,
    (2020, 48): 8600000,
    (2021, 12): 7050000, (2021, 24): 8590000, (2021, 36): 9230000,
    (2022, 12): 7680000, (2022, 24): 9370000,
    (2023, 12): 8250000,
}

claim_num = 1
for (ay, dev), total in sorted(triangle.items()):
    n_claims = 12
    # Split total into n_claims realistic amounts
    # Use Dirichlet-like split: generate n_claims random proportions
    raw = [random.random() for _ in range(n_claims)]
    raw_sum = sum(raw)
    # Convert to integer amounts that sum exactly to total
    amounts = [int(total * r / raw_sum) for r in raw]
    # Distribute rounding remainder across first few claims
    remainder = total - sum(amounts)
    for j in range(abs(remainder)):
        amounts[j % n_claims] += 1 if remainder > 0 else -1

    for amt in amounts:
        ws_claims.append([f"CLM-{ay}-{claim_num:04d}", ay, dev, amt])
        claim_num += 1

# ── EarnedPremium sheet ───────────────────────────────────────────────
ws_ep = wb.create_sheet("EarnedPremium")
ws_ep.append(["AccidentYear", "EarnedPremium", "ExpectedLossRatio"])
earned_data = [
    (2018, 10500000, 0.68),
    (2019, 11200000, 0.69),
    (2020, 12000000, 0.70),
    (2021, 13100000, 0.71),
    (2022, 14500000, 0.70),
    (2023, 15800000, 0.72),
]
for ay, ep, elr in earned_data:
    ws_ep.append([ay, ep, elr])

# ── Formatting ────────────────────────────────────────────────────────
bold_font = Font(bold=True)
header_fill = PatternFill(start_color='D9E1F2', end_color='D9E1F2', fill_type='solid')

for ws in [ws_claims, ws_ep]:
    for cell in ws[1]:
        cell.font = bold_font
        cell.fill = header_fill

# Currency format for CumulativeIncurred
for row in ws_claims.iter_rows(min_row=2, min_col=4, max_col=4):
    for cell in row:
        cell.number_format = '#,##0'

# Currency format for EarnedPremium
for row in ws_ep.iter_rows(min_row=2, min_col=2, max_col=2):
    for cell in row:
        cell.number_format = '#,##0'

# Percentage format for ExpectedLossRatio
for row in ws_ep.iter_rows(min_row=2, min_col=3, max_col=3):
    for cell in row:
        cell.number_format = '0%'

# Column widths
ws_claims.column_dimensions['A'].width = 18
ws_claims.column_dimensions['B'].width = 14
ws_claims.column_dimensions['C'].width = 18
ws_claims.column_dimensions['D'].width = 20
ws_ep.column_dimensions['A'].width = 14
ws_ep.column_dimensions['B'].width = 16
ws_ep.column_dimensions['C'].width = 20

wb.save("/home/ga/Documents/claims_data.xlsx")
print(f"Created claims_data.xlsx with {claim_num - 1} claim records across {len(triangle)} triangle cells.")
PYEOF

chown ga:ga "$INPUT_FILE" 2>/dev/null || true

# Kill any existing WPS instances for clean start
pkill -x et 2>/dev/null || true
sleep 1

# Launch WPS Spreadsheet with the input file
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et '$INPUT_FILE' &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l | grep -i "claims_data\|Spreadsheets"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "claims_data" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "claims_data" 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

# Dismiss any remaining WPS startup dialogs
source /workspace/scripts/launch_wps_for_task.sh
dismiss_wps_dialogs

echo "=== Task setup complete ==="
