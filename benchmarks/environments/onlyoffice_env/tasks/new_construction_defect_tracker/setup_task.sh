#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up New Construction Defect Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet with instructions
SHEET_PATH="$WORKSPACE_DIR/warranty_defects.xlsx"

cat > /tmp/create_defect_tracker.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Defect Tracker"

# Add a hint in cell A1 (will be overwritten by user)
ws['A1'] = "Create defect tracking columns here"
ws['A1'].font = Font(italic=True, color="999999")

# Add instructions in a separate area (will guide the user)
ws['A15'] = "TASK INSTRUCTIONS:"
ws['A15'].font = Font(bold=True, size=12)

instructions = [
    "1. Create header row with columns: Defect ID, Location, Category, Description, Date Noticed, Date Reported, Builder Response, Priority, Days Since Reported",
    "2. Enter 6 defect records:",
    "   - Basement Water Seepage (Structural, High, reported 45 days ago)",
    "   - HVAC Short-Cycling (HVAC, High, reported 30 days ago)",
    "   - Master Bedroom Door Won't Close (Cosmetic, Medium, reported 60 days ago)",
    "   - Kitchen Faucet Leaks (Plumbing, Medium, reported 20 days ago)",
    "   - Living Room Paint Bubbling (Cosmetic, Low, reported 15 days ago)",
    "   - Front Entry Light Fixture Flickering (Electrical, High, not yet reported)",
    "3. Use formula in 'Days Since Reported': =TODAY()-[Date Reported column]",
    "4. Format header row: Bold + Gray background",
    "5. Color-code Priority: High=Red, Medium=Orange, Low=Green",
    "6. Add summary section below data with: Total defects, High priority count, No response count",
    "7. Save file (Ctrl+S)"
]

for i, instruction in enumerate(instructions, start=16):
    ws[f'A{i}'] = instruction
    ws[f'A{i}'].font = Font(size=10)

# Set column widths for better readability
ws.column_dimensions['A'].width = 100

wb.save(sys.argv[1])
print(f"Defect tracker spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_defect_tracker.py
python3 /tmp/create_defect_tracker.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank defect tracker created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_defect_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_defect_task.log || true
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

echo "=== New Construction Defect Tracker Task Setup Complete ==="
echo "📝 Scenario: You are a homeowner documenting construction defects before 1-year warranty expires"
echo ""
echo "Required columns (A-I):"
echo "  A: Defect ID (DEF-001, DEF-002, etc.)"
echo "  B: Location (room/area)"
echo "  C: Category (Plumbing, Electrical, HVAC, Structural, Cosmetic, Other)"
echo "  D: Description (what's wrong)"
echo "  E: Date Noticed (MM/DD/YYYY)"
echo "  F: Date Reported (MM/DD/YYYY)"
echo "  G: Builder Response (No Response, Acknowledged, Scheduled, Repaired, Denied)"
echo "  H: Priority (High, Medium, Low)"
echo "  I: Days Since Reported (FORMULA: =TODAY()-F[row])"
echo ""
echo "Required defects to enter (6 total):"
echo "  1. Basement Water Seepage - Structural, High Priority, reported 45 days ago, No Response"
echo "  2. HVAC Short-Cycling - HVAC, High Priority, reported 30 days ago, Acknowledged"
echo "  3. Master Bedroom Door Won't Close - Cosmetic, Medium Priority, reported 60 days ago, Repaired"
echo "  4. Kitchen Faucet Leaks - Plumbing, Medium Priority, reported 20 days ago, Scheduled"
echo "  5. Living Room Paint Bubbling - Cosmetic, Low Priority, reported 15 days ago, No Response"
echo "  6. Front Entry Light Fixture Flickering - Electrical, High Priority, not yet reported"
echo ""
echo "Formatting requirements:"
echo "  - Header row: BOLD + light gray background"
echo "  - Priority values: High=RED, Medium=ORANGE/YELLOW, Low=GREEN text"
echo "  - Date columns: Use date format"
echo ""
echo "Summary section (add below data):"
echo "  - Total number of defects"
echo "  - Number of High Priority items"
echo "  - Number with 'No Response' status"
echo ""
echo "Save file (Ctrl+S) when complete"