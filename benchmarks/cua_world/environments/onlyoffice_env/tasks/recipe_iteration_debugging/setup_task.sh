#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Recipe Iteration Debugging Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the troubleshooting log spreadsheet
SHEET_PATH="$WORKSPACE_DIR/Cookie_Troubleshooting_Log.xlsx"

cat > /tmp/create_cookie_log.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Troubleshooting Log"

# Set column widths for readability
ws.column_dimensions['A'].width = 10
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 13
ws.column_dimensions['F'].width = 13
ws.column_dimensions['G'].width = 12
ws.column_dimensions['H'].width = 13
ws.column_dimensions['I'].width = 12
ws.column_dimensions['J'].width = 12
ws.column_dimensions['K'].width = 15
ws.column_dimensions['L'].width = 40
ws.column_dimensions['M'].width = 50

# Header row with styling
headers = [
    "Attempt", "Date", "Flour Type", "Butter Type", "Sugar Ratio",
    "Mixing Time", "Oven Temp", "Baking Time", "Room Temp", 
    "Humidity", "Outcome Score", "Outcome Notes", "Notes"
]

header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF")

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal='center', vertical='center')

# Attempt 1: Moderate success (baseline with bread flour, 350F)
ws.cell(row=2, column=1, value=1)
ws.cell(row=2, column=2, value="2024-01-15")
ws.cell(row=2, column=3, value="Bread Flour")
ws.cell(row=2, column=4, value="Unsalted")
ws.cell(row=2, column=5, value="1:2 (white:brown)")
ws.cell(row=2, column=6, value="5 min")
ws.cell(row=2, column=7, value="350°F")
ws.cell(row=2, column=8, value="12 min")
ws.cell(row=2, column=9, value="72°F")
ws.cell(row=2, column=10, value="45%")
ws.cell(row=2, column=11, value="7/10")
ws.cell(row=2, column=12, value="Good but slightly dry")
ws.cell(row=2, column=13, value="First attempt using grandma's recipe proportions")

# Attempt 2: Failed (switched to all-purpose flour)
ws.cell(row=3, column=1, value=2)
ws.cell(row=3, column=2, value="2024-01-22")
ws.cell(row=3, column=3, value="All-Purpose")
ws.cell(row=3, column=4, value="Unsalted")
ws.cell(row=3, column=5, value="1:2 (white:brown)")
ws.cell(row=3, column=6, value="5 min")
ws.cell(row=3, column=7, value="350°F")
ws.cell(row=3, column=8, value="12 min")
ws.cell(row=3, column=9, value="70°F")
ws.cell(row=3, column=10, value="42%")
ws.cell(row=3, column=11, value="3/10")
ws.cell(row=3, column=12, value="Too flat and spread too much")
ws.cell(row=3, column=13, value="Ran out of bread flour, tried all-purpose")

# Attempt 3: Best success (back to bread flour, lower temp)
ws.cell(row=4, column=1, value=3)
ws.cell(row=4, column=2, value="2024-02-05")
ws.cell(row=4, column=3, value="Bread Flour")
ws.cell(row=4, column=4, value="Unsalted")
ws.cell(row=4, column=5, value="1:2 (white:brown)")
ws.cell(row=4, column=6, value="5 min")
ws.cell(row=4, column=7, value="325°F")
ws.cell(row=4, column=8, value="14 min")
ws.cell(row=4, column=9, value="68°F")
ws.cell(row=4, column=10, value="40%")
ws.cell(row=4, column=11, value="9/10")
ws.cell(row=4, column=12, value="Perfect texture, closest to grandma's!")
ws.cell(row=4, column=13, value="Reduced oven temp to prevent over-browning")

# Attempt 4: Failed (partial data - used salted butter)
ws.cell(row=5, column=1, value=4)
ws.cell(row=5, column=2, value="2024-02-12")
ws.cell(row=5, column=3, value="???")  # Should be Bread Flour
ws.cell(row=5, column=4, value="???")  # Should be Salted
ws.cell(row=5, column=5, value="???")  # Same as attempt 3
ws.cell(row=5, column=6, value="???")  # Same as attempt 3
ws.cell(row=5, column=7, value="???")  # Same as attempt 3: 325°F
ws.cell(row=5, column=8, value="???")  # Same as attempt 3: 14 min
ws.cell(row=5, column=9, value="69°F")
ws.cell(row=5, column=10, value="38%")
ws.cell(row=5, column=11, value="2/10")
ws.cell(row=5, column=12, value="Too salty, weird aftertaste")
ws.cell(row=5, column=13, value="Same as attempt #3 but accidentally used salted butter from fridge")

# Attempt 5: Failed (partial data - high temp)
ws.cell(row=6, column=1, value=5)
ws.cell(row=6, column=2, value="2024-02-26")
ws.cell(row=6, column=3, value="")  # Should be Bread Flour
ws.cell(row=6, column=4, value="")  # Should be Unsalted
ws.cell(row=6, column=5, value="1:2 (white:brown)")
ws.cell(row=6, column=6, value="5 min")
ws.cell(row=6, column=7, value="???")  # Should be 375°F
ws.cell(row=6, column=8, value="???")  # Should be 10 min (shorter due to higher temp)
ws.cell(row=6, column=9, value="74°F")
ws.cell(row=6, column=10, value="50%")
ws.cell(row=6, column=11, value="4/10")
ws.cell(row=6, column=12, value="Over-browned, hard edges")
ws.cell(row=6, column=13, value="Back to unsalted butter. Tried 375°F to speed up baking (reduced time to 10 min)")

# Attempt 6: Good success (partial data - premium flour)
ws.cell(row=7, column=1, value=6)
ws.cell(row=7, column=2, value="2024-03-10")
ws.cell(row=7, column=3, value="???")  # Should be Bread Flour (King Arthur brand)
ws.cell(row=7, column=4, value="")  # Should be Unsalted
ws.cell(row=7, column=5, value="???")  # Same: 1:2
ws.cell(row=7, column=6, value="???")  # Same: 5 min
ws.cell(row=7, column=7, value="325°F")
ws.cell(row=7, column=8, value="14 min")
ws.cell(row=7, column=9, value="70°F")
ws.cell(row=7, column=10, value="43%")
ws.cell(row=7, column=11, value="8/10")
ws.cell(row=7, column=12, value="Excellent texture, slightly better rise")
ws.cell(row=7, column=13, value="Used King Arthur bread flour instead of generic store brand. Same temp/time as attempt #3")

# Add instructions section below the data
ws.cell(row=9, column=1, value="INSTRUCTIONS:")
ws.cell(row=9, column=1).font = Font(bold=True, size=12)

ws.cell(row=10, column=1, value="1. Fill in missing data (???) for attempts 4-6 using clues in the Notes column")
ws.cell(row=11, column=1, value="2. Create 'Variable Analysis' section below to compare which variables changed")
ws.cell(row=12, column=1, value="3. Create 'Conclusions' section identifying likely causes of failures")
ws.cell(row=13, column=1, value="4. Create 'Recommendation for Attempt #7' with specific changes to try")

# Save the workbook
wb.save(sys.argv[1])
print(f"Cookie troubleshooting log created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_cookie_log.py
python3 /tmp/create_cookie_log.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Cookie troubleshooting log created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_recipe_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_recipe_task.log || true
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

echo "=== Recipe Iteration Debugging Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  This is a systematic recipe troubleshooting log for chocolate chip cookies"
echo "  Attempts 1-3 are complete (showing the scientific method in action)"
echo "  Attempts 4-6 have missing data that needs to be filled from notes"
echo ""
echo "🎯 Your Goals:"
echo "  1. Fill in missing data (marked with '???') using clues in Notes column"
echo "  2. Create analysis section comparing variables across attempts"
echo "  3. Identify which variables correlate with success/failure"
echo "  4. Provide specific, evidence-based recommendation for attempt #7"
echo ""
echo "🔍 Pattern to discover:"
echo "  - Which flour type works best?"
echo "  - What is the optimal oven temperature?"
echo "  - Does butter type matter?"
echo "  - Are there any other critical variables?"