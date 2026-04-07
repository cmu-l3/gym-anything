#!/bin/bash
echo "=== Setting up restaurant_tip_pool_distribution task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

TARGET_FILE="/home/ga/Documents/tip_pool_week42.xlsx"
rm -f "$TARGET_FILE" 2>/dev/null || true

# Generate realistic restaurant payroll data
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Seed for reproducibility in evaluation
random.seed(42)

employees = [
    (101, "Alex Morgan", "Server"), (102, "Brian Chen", "Server"),
    (103, "Chloe Davis", "Server"), (104, "David Evans", "Bartender"),
    (105, "Elena Ford", "Bartender"), (106, "Fiona Grant", "Busser"),
    (107, "George Hill", "Busser"), (108, "Hannah Ives", "Host"),
    (109, "Ian Jones", "Runner"), (110, "Julia Katz", "Server"),
    (111, "Kevin Lee", "Server"), (112, "Liam Moore", "Server"),
    (113, "Mia Nelson", "Bartender"), (114, "Noah Owens", "Busser"),
    (115, "Olivia Page", "Host"), (116, "Paul Quinn", "Runner"),
    (117, "Quinn Reed", "Server"), (118, "Rachel Smith", "Server"),
    (119, "Sam Taylor", "Server"), (120, "Tom Vance", "Bartender"),
    (121, "Uma White", "Busser"), (122, "Victor Xing", "Host"),
    (123, "Wendy Young", "Runner"), (124, "Xavier Zane", "Server"),
    (125, "Yara Adams", "Server"), (126, "Zack Brown", "Bartender"),
    (127, "Amy Clark", "Busser"), (128, "Ben Diaz", "Host"),
    (129, "Cara Ellis", "Runner"), (130, "Dan Frank", "Server"),
    (131, "Eva Gomez", "Server"), (132, "Finn Harris", "Bartender")
]

roles = {
    "Server": 1.0,
    "Bartender": 1.5,
    "Busser": 0.5,
    "Host": 0.5,
    "Runner": 0.5
}

wb = Workbook()

# --- Sheet 1: Daily_Hours ---
ws_hours = wb.active
ws_hours.title = "Daily_Hours"
ws_hours.append(["Date", "Emp_ID", "Name", "Role", "Hours"])

dates = [f"2023-10-{day:02d}" for day in range(16, 23)]
for d in dates:
    # Randomly select who worked this day
    daily_staff = random.sample(employees, k=random.randint(18, 26))
    for emp in daily_staff:
        # Generate realistic shift hours (e.g., 4.5 to 8.5)
        hours = round(random.uniform(4.0, 9.0) * 2) / 2
        ws_hours.append([d, emp[0], emp[1], emp[2], hours])

# --- Sheet 2: Role_Points ---
ws_roles = wb.create_sheet("Role_Points")
ws_roles.append(["Role", "Points"])
for role, pts in roles.items():
    ws_roles.append([role, pts])

# --- Sheet 3: Summary ---
ws_summary = wb.create_sheet("Summary")

# Pool total header
ws_summary["A1"] = "Total Weekly Tip Pool"
ws_summary["A1"].font = Font(bold=True)
ws_summary["B1"] = 15450.25
ws_summary["B1"].number_format = '$#,##0.00'
ws_summary["B1"].font = Font(bold=True, color="008000")

# Table headers
ws_summary.append([]) # Row 2 empty
headers = ["Emp_ID", "Name", "Role"]
ws_summary.append(headers)

# Formatting headers
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color='4F81BD', end_color='4F81BD', fill_type='solid')
for col_num, cell in enumerate(ws_summary[3], 1):
    cell.font = header_font
    cell.fill = header_fill

# Add employee list
for emp in employees:
    ws_summary.append([emp[0], emp[1], emp[2]])

# Adjust widths
ws_hours.column_dimensions['C'].width = 18
ws_summary.column_dimensions['A'].width = 25 # wider for the A1 title
ws_summary.column_dimensions['B'].width = 18
ws_summary.column_dimensions['C'].width = 12
ws_summary.column_dimensions['D'].width = 14
ws_summary.column_dimensions['E'].width = 10
ws_summary.column_dimensions['F'].width = 14
ws_summary.column_dimensions['G'].width = 16

wb.save('/home/ga/Documents/tip_pool_week42.xlsx')
print(f"Created tip pool spreadsheet.")
PYEOF

chown ga:ga "$TARGET_FILE" 2>/dev/null || true

# Start WPS Spreadsheet
if ! pgrep -x "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$TARGET_FILE' &"
    sleep 6
fi

# Focus and Maximize the window
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss potential dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Ensure window is visible
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="