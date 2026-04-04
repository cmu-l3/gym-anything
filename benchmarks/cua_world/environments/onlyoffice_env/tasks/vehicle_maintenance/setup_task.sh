#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Vehicle Maintenance Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet for the user to work with
SHEET_PATH="$WORKSPACE_DIR/vehicle_maintenance_log.xlsx"

cat > /tmp/create_maintenance_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Maintenance Log"

# Create a completely blank spreadsheet
# The user will add everything from scratch

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_maintenance_sheet.py
python3 /tmp/create_maintenance_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_maintenance_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_maintenance_task.log || true
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

echo "=== Vehicle Maintenance Log Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create column headers in row 1:"
echo "     - A1: Date"
echo "     - B1: Service Type"
echo "     - C1: Mileage"
echo "     - D1: Cost ($)"
echo ""
echo "  2. Add at least 5 maintenance records (rows 2-6 or more):"
echo "     Example data:"
echo "     - 2024-01-15 | Oil Change | 45000 | 45.00"
echo "     - 2024-03-20 | Tire Rotation | 48000 | 80.00"
echo "     - 2024-06-10 | Brake Service | 51000 | 250.00"
echo "     - 2024-07-05 | Air Filter | 52500 | 35.00"
echo "     - 2024-09-12 | Inspection | 55000 | 50.00"
echo ""
echo "  3. Below your data, create summary calculations:"
echo "     - Label + Formula for Total Cost: =SUM(D2:D6)"
echo "     - Label + Formula for Average Cost: =AVERAGE(D2:D6)"
echo "     - Label + Formula for Highest Cost: =MAX(D2:D6)"
echo ""
echo "  4. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 Tip: Adjust cell ranges in formulas to match your actual data rows"