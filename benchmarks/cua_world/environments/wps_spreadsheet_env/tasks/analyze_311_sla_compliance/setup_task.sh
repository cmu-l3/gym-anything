#!/bin/bash
echo "=== Setting up analyze_311_sla_compliance task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

DATA_FILE="/home/ga/Documents/chicago_311_potholes.xlsx"
rm -f "$DATA_FILE" 2>/dev/null || true
mkdir -p /home/ga/Documents

# Generate a realistic 311 dataset via Python
python3 << 'PYEOF'
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from datetime import datetime, timedelta
import random

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Pothole_Data"

# Add headers
headers = ["SR_Number", "Created_Date", "Closed_Date", "Status", "Ward", "Police_District"]
ws.append(headers)

# Apply header formatting
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color='4F81BD', end_color='4F81BD', fill_type='solid')
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Generate 100 rows of realistic data
base_date = datetime(2023, 5, 1)
random.seed(101)

for i in range(1, 101):
    sr = f"SR23-{random.randint(100000, 999999)}"
    created = base_date + timedelta(days=random.randint(0, 60))
    status = random.choices(["Completed", "Open"], weights=[0.85, 0.15])[0]
    ward = random.randint(1, 5)  # Restrict to Wards 1-5 for simplicity in this task
    pd = random.randint(1, 20)
    
    if status == "Completed":
        # Introduce a mix of SLA met and breached
        days_to_close = random.choices([random.randint(1, 7), random.randint(8, 20)], weights=[0.7, 0.3])[0]
        closed = created + timedelta(days=days_to_close)
        ws.append([sr, created.strftime("%Y-%m-%d"), closed.strftime("%Y-%m-%d"), status, ward, pd])
    else:
        ws.append([sr, created.strftime("%Y-%m-%d"), "", status, ward, pd])

# Auto-adjust column widths
for col_letter, width in zip(['A', 'B', 'C', 'D', 'E', 'F'], [16, 14, 14, 12, 8, 14]):
    ws.column_dimensions[col_letter].width = width

wb.save("/home/ga/Documents/chicago_311_potholes.xlsx")
print("Generated 100 rows of Chicago 311 pothole data.")
PYEOF

chown ga:ga "$DATA_FILE" 2>/dev/null || true

# Save initial state of the file
INITIAL_MTIME=$(stat -c %Y "$DATA_FILE" 2>/dev/null || echo "0")
echo "$INITIAL_MTIME" > /tmp/initial_mtime.txt

# Start WPS Spreadsheet if not running
if ! pgrep -x "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$DATA_FILE' &"
    sleep 6
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "chicago_311_potholes"; then
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "chicago_311_potholes" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "chicago_311_potholes" 2>/dev/null || true

# Take initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="