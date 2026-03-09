#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Wildlife Intake Analysis Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy wildlife intake spreadsheet
SHEET_PATH="$WORKSPACE_DIR/wildlife_intake_spring.xlsx"

cat > /tmp/create_wildlife_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font
import random
import sys

wb = Workbook()
ws = wb.active
ws.title = "Spring Intakes"

# Add headers
headers = ["Intake ID", "Date Admitted", "Species", "Age Class", "Intake Reason", "Outcome", "Date Released", "Notes"]
for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)

# Real-world messy data with intentional issues
intake_data = [
    # [ID, Date Admitted, Species, Age Class, Reason, Outcome, Date Released, Notes]
    [1, "03/15/2024", "Raccoon", "Juvenile", "Orphaned", "Released", "04/12/2024", "Healthy weight gain"],
    [2, "March 18 2024", "RACCOON", "", "Hit by car", "Died", "", "Severe head trauma"],
    [3, "3/20/24", "Eastern Gray Squirrel", "Nestling", "Cat attack", "Released", "04/25/2024", ""],
    [4, "03/22/2024", "Mallard Duck", "Adult", "Window strike", "", "", "Still in care - wing injury"],
    [5, "3/25/24", "MALL", "Juvenile", "Orphaned", "Released", "04/30/2024", "Imprinted - soft release"],
    [6, "", "", "", "", "", "", ""],  # Blank row
    [7, "March 28 2024", "E.G. Squirrel", "Juvenile", "Fell from nest", "Released", "05/02/2024", ""],
    [8, "03/30/2024", "Virginia Opossum", "Adult", "HBC", "Euthanized", "03/30/2024", "Spinal injury"],
    [9, "4/1/24", "Racc", "Adult", "Unknown", "Released", "04/15/2024", ""],
    [10, "April 3 2024", "Red-tailed Hawk", "Adult", "Hit by car", "Died", "04/05/2024", "Internal bleeding"],
    [11, "04/05/2024", "Eastern Gray Squirrel", "", "Orphaned", "Released", "05/10/2024", "Raised in group"],
    [12, "4/8/24", "Raccoon", "Juvenile", "Orphaned", "Released", "05/15/2024", ""],
    [13, "", "", "", "", "", "", ""],  # Blank row
    [14, "April 10 2024", "Box Turtle", "Adult", "Hit by car", "Released", "05/20/2024", "Shell fracture healed"],
    [15, "04/12/2024", "MALL", "Nestling", "Cat attack", "", "", "Still in care"],
    [16, "4/15/24", "Red-tailed Hawk", "Juvenile", "Fell from nest", "Released", "06/01/2024", ""],
    [17, "April 18 2024", "Racn", "Adult", "HBC", "Released", "05/01/2024", ""],
    [18, "04/20/2024", "Virginia Opossum", "Juvenile", "Orphaned", "Released", "05/25/2024", ""],
    [19, "4/22/24", "Eastern Gray Squirrel", "Nestling", "Fell from nest", "Died", "04/23/2024", "Too young - dehydrated"],
    [20, "April 25 2024", "", "Adult", "Window strike", "Released", "05/10/2024", ""],  # Missing species
    [21, "04/28/2024", "Mallard Duck", "Adult", "Cat attack", "Released", "05/30/2024", ""],
    [22, "4/30/24", "E.G. Squirrel", "", "Orphaned", "Released", "06/05/2024", ""],
    [23, "May 2 2024", "Box Turtle", "Adult", "Lawnmower", "Released", "06/10/2024", "Minor shell damage"],
    [24, "", "", "", "", "", "", ""],  # Blank row
    [25, "05/05/2024", "RACCOON", "Juvenile", "Orphaned", "", "", "Currently feeding"],
    [26, "5/8/24", "Red-tailed Hawk", "Adult", "Unknown", "Transferred", "05/15/2024", "Sent to raptor center"],
    [27, "May 10 2024", "Virginia Opossum", "Juvenile", "Cat attack", "Released", "06/12/2024", ""],
    [28, "05/12/2024", "Mallard Duck", "Juvenile", "Orphaned", "Released", "06/15/2024", ""],
    [29, "5/15/24", "Eastern Gray Squirrel", "Nestling", "Fell from nest", "Released", "06/20/2024", ""],
    [30, "May 18 2024", "Raccoon", "Adult", "HBC", "Euthanized", "05/18/2024", "Non-viable injuries"],
]

# Write data to spreadsheet
for row_idx, row_data in enumerate(intake_data, start=2):
    for col_idx, value in enumerate(row_data, start=1):
        ws.cell(row=row_idx, column=col_idx, value=value)

# Adjust column widths for readability
ws.column_dimensions['A'].width = 10
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 25
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 18
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 18
ws.column_dimensions['H'].width = 30

# Add instructions at the bottom
ws['A35'] = "GRANT APPLICATION DATA NEEDED:"
ws['A36'] = "1. Species Category Summary (Mammals/Birds/Reptiles) - put in rows 40-44"
ws['A37'] = "2. Success Rate (Released / Completed Cases %) - put in rows 46-50"
ws['A38'] = "3. Top 3 Most Frequent Species - put in rows 52-55"
ws['A39'] = "4. Average Days in Care - put in row 57"

wb.save(sys.argv[1])
print(f"Wildlife intake spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_wildlife_sheet.py
python3 /tmp/create_wildlife_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Wildlife intake spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_wildlife_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_wildlife_task.log || true
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

echo "=== Wildlife Intake Analysis Task Setup Complete ==="
echo "📝 Scenario: You're a wildlife rehab coordinator preparing a grant application."
echo "📝 The spring intake log is messy (mixed formats, abbreviations, blanks)."
echo ""
echo "🎯 Required Analysis (see rows 35-39 for details):"
echo "  1. Create Species Category Summary in rows 40-44 (Mammals/Birds/Reptiles counts)"
echo "  2. Calculate Success Rate in rows 46-50 (% of Released / Total Completed)"
echo "  3. List Top 3 Species in rows 52-55 (ranked by frequency)"
echo "  4. Calculate Average Days in Care in row 57"
echo ""
echo "🔧 Data Cleaning Required:"
echo "  5. Insert Species Category column (as new column D)"
echo "  6. Add Days in Care column (calculate from admit/release dates)"
echo ""
echo "💡 Tips:"
echo "  - Standardize species names (Raccoon/RACCOON/Racc are same)"
echo "  - Mammals: Raccoon, Squirrel, Opossum"
echo "  - Birds: Mallard Duck, Red-tailed Hawk"
echo "  - Reptiles: Box Turtle"
echo "  - Exclude blank outcomes from success rate (still in care)"
echo "  - Use date formulas to calculate days"
echo ""
echo "💾 Save when complete (Ctrl+S)"