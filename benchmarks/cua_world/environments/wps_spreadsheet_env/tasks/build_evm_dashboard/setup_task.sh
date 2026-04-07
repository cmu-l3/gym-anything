#!/bin/bash
echo "=== Setting up build_evm_dashboard task ==="

export DISPLAY=:1
DATA_FILE="/home/ga/Documents/project_evm_data.xlsx"

# Remove any existing file
rm -f "$DATA_FILE" 2>/dev/null || true

# Generate realistic construction EVM data dynamically
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()

# --- SHEET 1: BUDGET ---
ws_budget = wb.active
ws_budget.title = 'Project_Budget'

headers_budget = ['WBS Code', 'Description', 'BAC', 'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'M10', 'M11', 'M12']
ws_budget.append(headers_budget)

# Create 18 WBS rows (Total BAC = 2,400,000)
for i in range(1, 11):
    ws_budget.append([f"1.{i}", f"Phase 1 Task {i}", 100000] + [12500]*8 + [0]*4)
for i in range(1, 6):
    ws_budget.append([f"2.{i}", f"Phase 2 Task {i}", 150000] + [15000]*8 + [7500]*4)
for i in range(1, 3):
    ws_budget.append([f"3.{i}", f"Phase 3 Task {i}", 200000] + [6250]*8 + [37500]*4)
ws_budget.append(["4.1", "Final Phase Task 1", 250000] + [11250]*8 + [40000]*4)

ws_budget.append(["", "TOTAL", "=SUM(C2:C19)", "=SUM(D2:D19)", "=SUM(E2:E19)", "=SUM(F2:F19)", "=SUM(G2:G19)", "=SUM(H2:H19)", "=SUM(I2:I19)", "=SUM(J2:J19)", "=SUM(K2:K19)", "=SUM(L2:L19)", "=SUM(M2:M19)", "=SUM(N2:N19)", "=SUM(O2:O19)"])

# --- SHEET 2: ACTUALS ---
ws_actuals = wb.create_sheet('Project_Actuals')
headers_act = ['WBS Code', 'Description', 'M1 Act', 'M2 Act', 'M3 Act', 'M4 Act', 'M5 Act', 'M6 Act', 'M7 Act', 'M8 Act', 'Cumul AC', '% Complete']
ws_actuals.append(headers_act)

for i in range(1, 11):
    ws_actuals.append([f"1.{i}", f"Phase 1 Task {i}"] + [13750]*8 + ["=SUM(C2:J2)", 1.0])
for i in range(1, 6):
    ws_actuals.append([f"2.{i}", f"Phase 2 Task {i}"] + [8750]*8 + ["=SUM(C12:J12)", 0.4])
for i in range(1, 3):
    ws_actuals.append([f"3.{i}", f"Phase 3 Task {i}"] + [1187.5]*8 + ["=SUM(C17:J17)", 0.05])
ws_actuals.append(["4.1", "Final Phase Task 1"] + [0]*8 + ["=SUM(C19:J19)", 0.086])

ws_actuals.append(["", "TOTAL", "=SUM(C2:C19)", "=SUM(D2:D19)", "=SUM(E2:E19)", "=SUM(F2:F19)", "=SUM(G2:G19)", "=SUM(H2:H19)", "=SUM(I2:I19)", "=SUM(J2:J19)", "=SUM(K2:K19)"])

# Styling
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9E1F2', end_color='D9E1F2', fill_type='solid')

for ws in [ws_budget, ws_actuals]:
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal='center')
    ws.column_dimensions['A'].width = 12
    ws.column_dimensions['B'].width = 25

wb.save('/home/ga/Documents/project_evm_data.xlsx')
print("EVM data file generated successfully.")
PYEOF

chown ga:ga "$DATA_FILE" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Start WPS Spreadsheet
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$DATA_FILE' &"
    sleep 6
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "project_evm_data"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "project_evm_data" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "project_evm_data" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="