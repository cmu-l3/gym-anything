#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Meal Prep Macro Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create meal database CSV
cat > /home/ga/Documents/meal_database.csv << 'CSVEOF'
Meal Name,Protein (g),Carbs (g),Fats (g),Cost ($)
Chicken & Rice Bowl,42,58,12,6.50
Salmon & Sweet Potato,38,45,18,8.75
Turkey Chili,35,38,14,5.25
Greek Pasta Salad,28,62,16,4.80
Beef Stir-Fry,45,42,22,7.90
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/meal_database.csv
sudo chmod 644 /home/ga/Documents/meal_database.csv

echo "✅ Created meal database CSV"

# Create a blank ODS file for the meal plan
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Meal Plan"
table = Table(name="Meal Plan")
doc.spreadsheet.addElement(table)

# Add empty rows
for _ in range(30):
    row = TableRow()
    for _ in range(12):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/meal_prep_plan.ods")
print("Created blank meal plan ODS file")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/meal_prep_plan.ods
sudo chmod 666 /home/ga/Documents/meal_prep_plan.ods

# Launch LibreOffice Calc with the blank meal plan
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/meal_prep_plan.ods > /tmp/calc_meal_prep.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_meal_prep.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Meal Prep Macro Calculator Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "  1. Import meal database: File → Open → /home/ga/Documents/meal_database.csv"
echo "  2. Create meal plan table with columns: Day, Meal Name, Portion Size, Protein, Carbs, Fats, Cost"
echo "  3. Plan 5 days (Monday-Friday) selecting meals from database"
echo "  4. Use VLOOKUP formulas to calculate macros: =VLOOKUP(meal_name, database, column, FALSE) * portion"
echo "  5. Add SUM formulas for totals of each macro"
echo "  6. Daily targets: Protein 180g, Carbs 220g, Fats 60g"
echo "  7. Apply conditional formatting (green if within ±5g of target)"
echo "  8. Adjust portion sizes to hit all three macro targets"
echo ""
echo "🎯 Goal: All three macros showing GREEN (within ±5g of target)"
echo "💡 Tip: Start with 1.0 portions and adjust iteratively"