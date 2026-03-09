#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Vehicle Service History Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
RECEIPTS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$RECEIPTS_DIR"

# Create receipts file with raw maintenance data
RECEIPTS_PATH="$RECEIPTS_DIR/service_receipts.txt"

cat > "$RECEIPTS_PATH" << 'EOF'
VEHICLE SERVICE RECEIPTS - 2018 Honda Civic (VIN: 1HGCV1F3XJA123456)
========================================================================

Receipt 1:
Date: 03/15/2022
Odometer: 45,230 miles
Service: Oil Change + Filter Replacement
Shop: Jiffy Lube - Main Street
Cost: $45.99
Notes: Synthetic blend 5W-30, new oil filter

Receipt 2:
Date: 06/22/2022
Odometer: 48,105 miles
Service: Tire Rotation
Shop: Discount Tire Co.
Cost: $0.00 (complimentary service)
Notes: All tires rotated, pressure checked and adjusted

Receipt 3:
Date: 09/08/2022
Odometer: 51,340 miles
Service: Oil Change + Multi-Point Inspection
Shop: Honda Dealership Service Center
Cost: $78.50
Notes: Full synthetic oil, inspection passed

Receipt 4:
Date: 12/01/2022
Odometer: 54,890 miles
Service: Brake Pad Replacement (front axle)
Shop: Midas Auto Service
Cost: $285.00
Notes: Front brake pads worn, rotors resurfaced

Receipt 5:
Date: 03/20/2023
Odometer: 58,120 miles
Service: Oil Change + Air Filter Replacement
Shop: Jiffy Lube - Main Street
Cost: $62.30
Notes: Synthetic blend oil, new engine air filter

Receipt 6:
Date: 07/10/2023
Odometer: 61,450 miles
Service: Coolant System Flush + Hose Inspection
Shop: Honda Dealership Service Center
Cost: $145.00
Notes: Old coolant replaced, all hoses inspected - good condition

Receipt 7:
Date: 10/25/2023
Odometer: 64,780 miles
Service: Oil Change + Tire Rotation
Shop: Honda Dealership Service Center
Cost: $85.00
Notes: Full synthetic oil, tires rotated

Receipt 8:
Date: 01/30/2024
Odometer: 68,200 miles
Service: Battery Replacement
Shop: AutoZone
Cost: $189.99
Notes: Old battery failed load test, new 3-year warranty battery installed

Receipt 9:
Date: 05/15/2024
Odometer: 71,540 miles
Service: Oil Change + Multi-point Inspection
Shop: Jiffy Lube - Main Street
Cost: $52.75
Notes: Synthetic blend oil, all fluid levels checked

Receipt 10:
Date: 08/22/2024
Odometer: 74,320 miles
Service: Transmission Fluid Service
Shop: Honda Dealership Service Center
Cost: $195.50
Notes: Transmission fluid drained and replaced, filter cleaned

========================================================================
NOTES FOR ORGANIZING:
- Need to track these for warranty claim on recurring engine light issue
- Mechanic appointment tomorrow morning at 9 AM
- Also planning to sell car next month - organized records increase value
- Total invested in maintenance should be around $1,140
========================================================================
EOF

chown ga:ga "$RECEIPTS_PATH"

echo "✅ Service receipts file created at: $RECEIPTS_PATH"

# Create a blank XLSX file (OnlyOffice will open it)
SHEET_PATH="$WORKSPACE_DIR/car_service_log.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Service History"

# Create completely blank spreadsheet - user must add everything
# This makes the task more realistic (starting from scratch)

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Also open the receipts file in a text editor so agent can reference it
echo "Opening receipts file in text editor for reference..."
su - ga -c "DISPLAY=:1 xdg-open '$RECEIPTS_PATH' > /tmp/text_editor.log 2>&1 &" || true
sleep 2

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_vehicle_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_vehicle_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Vehicle Service History Task Setup Complete ==="
echo "📝 Task Instructions:"
echo "  1. Open and read /home/ga/Documents/service_receipts.txt (should already be open)"
echo "  2. In the spreadsheet, create column headers:"
echo "     - Date, Odometer, Service Type, Provider, Cost, (optional: Notes)"
echo "  3. Enter all 10 service records from the receipts file"
echo "  4. Add a calculated column 'Miles Since Last Service' with formulas"
echo "  5. Add a row at the bottom with 'TOTAL' label and SUM formula for costs"
echo "  6. Format:"
echo "     - Make headers BOLD"
echo "     - Format Cost column as CURRENCY ($X.XX)"
echo "  7. Sort all records by Date (oldest to newest)"
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected Results:"
echo "  - 10 service records entered"
echo "  - Total maintenance cost: $1,140.03"
echo "  - Records in chronological order (03/15/2022 to 08/22/2024)"
echo "  - Professional appearance suitable for mechanic/buyer review"