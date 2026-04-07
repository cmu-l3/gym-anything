#!/bin/bash
set -e
echo "=== Setting up risk assessment matrix task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the hazard register spreadsheet
python3 << 'PYEOF'
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Hazards"

# Headers
headers = ["Hazard ID", "Hazard Description", "Location", "Category",
           "Likelihood (1-5)", "Severity (1-5)", "Risk Score", "Risk Level", "Controls Required"]

header_font_white = Font(bold=True, size=11, color="FFFFFF")
header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")

for col, header in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col, value=header)
    cell.font = header_font_white
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)

# Hazard data - based on OSHA Focus Four construction hazards
hazards = [
    ("H001", "Falls from scaffolding without guardrails", "Building A - Level 5", "Falls", 4, 5),
    ("H002", "Falling debris from upper floor demolition", "Building A - Ground", "Struck-by", 3, 4),
    ("H003", "Trench collapse in unshored excavation", "Excavation Zone North", "Caught-in/between", 2, 5),
    ("H004", "Contact with overhead 13.8kV power lines", "Site Perimeter East", "Electrocution", 2, 5),
    ("H005", "Slip on wet freshly poured concrete", "Building B - Slab", "Falls", 4, 3),
    ("H006", "Struck by swinging crane load", "Staging Area", "Struck-by", 3, 5),
    ("H007", "Hand caught in concrete mixer drum", "Batch Plant", "Caught-in/between", 2, 4),
    ("H008", "Electric shock from defective power tool", "Building A - Level 3", "Electrocution", 3, 4),
    ("H009", "Fall from unprotected roof edge", "Building B - Roof", "Falls", 3, 5),
    ("H010", "Hit by reversing dump truck", "Haul Road", "Struck-by", 3, 4),
    ("H011", "Clothing caught in rotating auger", "Foundation Zone", "Caught-in/between", 2, 4),
    ("H012", "Contact with damaged extension cord", "Temporary Power Area", "Electrocution", 3, 3),
    ("H013", "Ladder tip-over from improper setup", "Building A - Level 2", "Falls", 4, 4),
    ("H014", "Flying fragments from abrasive cutting disc", "Steel Fabrication Yard", "Struck-by", 4, 3),
    ("H015", "Worker pinned between vehicle and barrier wall", "Loading Dock", "Caught-in/between", 2, 5),
    ("H016", "Arc flash during electrical panel termination", "Electrical Room B", "Electrocution", 2, 5),
    ("H017", "Fall through unprotected floor opening", "Building A - Level 4", "Falls", 3, 4),
    ("H018", "Dropped hand tool from elevated work platform", "Building B - Level 6", "Struck-by", 4, 3),
    ("H019", "Limb entanglement in excavator bucket linkage", "Excavation Zone South", "Caught-in/between", 2, 4),
    ("H020", "Wet conditions near temporary wiring splices", "Mechanical Room", "Electrocution", 3, 4),
    ("H021", "Unstable formwork collapse during pour", "Building A - Level 6", "Falls", 3, 5),
    ("H022", "Nail gun ricochet from hardened steel", "Building B - Framing", "Struck-by", 3, 3),
    ("H023", "Limb caught in conveyor belt at gravel plant", "Batch Plant", "Caught-in/between", 2, 5),
    ("H024", "Improper grounding of portable generator", "Staging Area", "Electrocution", 2, 4),
    ("H025", "Fall from aerial work platform due to wind", "Building A - Exterior", "Falls", 3, 4),
    ("H026", "Steel beam dropped during erection", "Building B - Level 4", "Struck-by", 2, 5),
    ("H027", "Soil cave-in during pipe laying operations", "Utility Trench West", "Caught-in/between", 3, 5),
    ("H028", "Contact with energized rebar during welding", "Building A - Foundation", "Electrocution", 2, 4),
    ("H029", "Slip on icy steel beam during winter work", "Building B - Level 7", "Falls", 3, 5),
    ("H030", "Struck by backhoe boom during swing", "Excavation Zone North", "Struck-by", 2, 4),
]

for i, (hid, desc, loc, cat, lik, sev) in enumerate(hazards, 2):
    ws.cell(row=i, column=1, value=hid)
    ws.cell(row=i, column=2, value=desc)
    ws.cell(row=i, column=3, value=loc)
    ws.cell(row=i, column=4, value=cat)
    ws.cell(row=i, column=5, value=lik)
    ws.cell(row=i, column=6, value=sev)

# Set column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 48
ws.column_dimensions['C'].width = 26
ws.column_dimensions['D'].width = 20
ws.column_dimensions['E'].width = 16
ws.column_dimensions['F'].width = 14
ws.column_dimensions['G'].width = 14
ws.column_dimensions['H'].width = 14
ws.column_dimensions['I'].width = 20

# Freeze top row
ws.freeze_panes = "A2"

wb.save("/home/ga/Documents/hazard_register.xlsx")
print("hazard_register.xlsx created successfully with 30 hazards")
PYEOF

chown ga:ga /home/ga/Documents/hazard_register.xlsx

# Record initial file state
md5sum /home/ga/Documents/hazard_register.xlsx > /tmp/initial_file_hash.txt
stat -c %Y /home/ga/Documents/hazard_register.xlsx > /tmp/initial_file_mtime.txt

# Wait for desktop
sleep 2

# Open the file in WPS Spreadsheet
echo "Opening hazard_register.xlsx in WPS Spreadsheet..."
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et /home/ga/Documents/hazard_register.xlsx &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "hazard_register"; then
        break
    fi
    sleep 1
done

sleep 2

# Maximize the WPS window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="