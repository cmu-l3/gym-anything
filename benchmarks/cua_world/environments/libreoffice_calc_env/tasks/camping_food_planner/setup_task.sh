#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Camping Food Planner Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create pre-populated ODS file using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, CurrencyStyle, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a sheet named "Food Planning"
table = Table(name="Food Planning")

def create_text_cell(text):
    """Create cell with text value"""
    cell = TableCell()
    if text is not None and text != "":
        p = P(text=str(text))
        cell.addElement(p)
    return cell

def create_number_cell(value):
    """Create cell with numeric value"""
    cell = TableCell(valuetype="float", value=str(value))
    p = P(text=str(value))
    cell.addElement(p)
    return cell

def create_empty_row(num_cells=10):
    """Create empty row with specified number of cells"""
    row = TableRow()
    for _ in range(num_cells):
        row.addElement(create_text_cell(""))
    return row

# Add header and trip parameters (Rows 1-3)
row1 = TableRow()
row1.addElement(create_text_cell("CAMPING TRIP FOOD PLANNER"))
for _ in range(9):
    row1.addElement(create_text_cell(""))
table.addElement(row1)

table.addElement(create_empty_row())

row3 = TableRow()
row3.addElement(create_text_cell("Trip Duration (days):"))
row3.addElement(create_number_cell(5))
row3.addElement(create_text_cell("Total Participants:"))
row3.addElement(create_number_cell(7))
row3.addElement(create_text_cell("Safety Factor:"))
row3.addElement(create_number_cell(1.1))
for _ in range(4):
    row3.addElement(create_text_cell(""))
table.addElement(row3)

table.addElement(create_empty_row())

# Participants section (Rows 5-13)
row5 = TableRow()
row5.addElement(create_text_cell("PARTICIPANTS"))
for _ in range(9):
    row5.addElement(create_text_cell(""))
table.addElement(row5)

# Participants header
row6 = TableRow()
row6.addElement(create_text_cell("Name"))
row6.addElement(create_text_cell("Vegetarian"))
row6.addElement(create_text_cell("Gluten-Free"))
for _ in range(7):
    row6.addElement(create_text_cell(""))
table.addElement(row6)

# Participants data
participants = [
    ("Alex", "No", "No"),
    ("Beth", "Yes", "No"),
    ("Chris", "No", "Yes"),
    ("Dana", "Yes", "Yes"),
    ("Eli", "No", "No"),
    ("Fiona", "No", "No"),
    ("Greg", "Yes", "No")
]

for name, veg, gf in participants:
    row = TableRow()
    row.addElement(create_text_cell(name))
    row.addElement(create_text_cell(veg))
    row.addElement(create_text_cell(gf))
    for _ in range(7):
        row.addElement(create_text_cell(""))
    table.addElement(row)

table.addElement(create_empty_row())

# Food items section (Rows 15+)
row15 = TableRow()
row15.addElement(create_text_cell("FOOD ITEMS"))
for _ in range(9):
    row15.addElement(create_text_cell(""))
table.addElement(row15)

# Food items header
row16 = TableRow()
row16.addElement(create_text_cell("Item"))
row16.addElement(create_text_cell("Unit"))
row16.addElement(create_text_cell("Unit Cost ($)"))
row16.addElement(create_text_cell("Servings/Person/Day"))
row16.addElement(create_text_cell("Eaters Count"))
row16.addElement(create_text_cell("Total Quantity"))
row16.addElement(create_text_cell("Total Cost ($)"))
for _ in range(3):
    row16.addElement(create_text_cell(""))
table.addElement(row16)

# Food items data
food_items = [
    ("Rice", "cups", 0.25, 0.5, 7),
    ("Pasta", "lbs", 1.50, 0.3, 5),  # Gluten-free excluded (2 people)
    ("Chicken", "lbs", 3.00, 0.4, 4),  # Vegetarians excluded (3 people)
    ("Black Beans", "cans", 1.20, 0.5, 7),
    ("Oatmeal", "cups", 0.30, 0.75, 7),
    ("Trail Mix", "lbs", 6.00, 0.2, 7),
    ("Cooking Oil", "cups", 0.50, 0.1, 7),
    ("Coffee", "oz", 0.40, 2.0, 6)  # 1 person doesn't drink coffee
]

for item, unit, cost, servings, eaters in food_items:
    row = TableRow()
    row.addElement(create_text_cell(item))
    row.addElement(create_text_cell(unit))
    row.addElement(create_number_cell(cost))
    row.addElement(create_number_cell(servings))
    row.addElement(create_number_cell(eaters))
    row.addElement(create_text_cell(""))  # Total Quantity - to be filled with formula
    row.addElement(create_text_cell(""))  # Total Cost - to be filled with formula
    for _ in range(3):
        row.addElement(create_text_cell(""))
    table.addElement(row)

table.addElement(create_empty_row())
table.addElement(create_empty_row())

# Shopping list section
row27 = TableRow()
row27.addElement(create_text_cell("SHOPPING LIST"))
for _ in range(9):
    row27.addElement(create_text_cell(""))
table.addElement(row27)

row28 = TableRow()
row28.addElement(create_text_cell("Item"))
row28.addElement(create_text_cell("Quantity to Buy"))
row28.addElement(create_text_cell("Total Cost ($)"))
for _ in range(7):
    row28.addElement(create_text_cell(""))
table.addElement(row28)

# Add placeholder rows for shopping list
for _ in range(8):
    table.addElement(create_empty_row())

table.addElement(create_empty_row())

# Cost per person section
row38 = TableRow()
row38.addElement(create_text_cell("COST PER PERSON"))
for _ in range(9):
    row38.addElement(create_text_cell(""))
table.addElement(row38)

row39 = TableRow()
row39.addElement(create_text_cell("Name"))
row39.addElement(create_text_cell("Amount Owed ($)"))
for _ in range(8):
    row39.addElement(create_text_cell(""))
table.addElement(row39)

# Add placeholder rows for cost breakdown
for _ in range(7):
    table.addElement(create_empty_row())

# Add more empty rows for working space
for _ in range(10):
    table.addElement(create_empty_row())

doc.spreadsheet.addElement(table)

# Save the file
output_path = "/home/ga/Documents/camping_food_plan.ods"
doc.save(output_path)
print(f"✅ Created camping food planner template: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/camping_food_plan.ods
sudo chmod 666 /home/ga/Documents/camping_food_plan.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/camping_food_plan.ods > /tmp/calc_camping_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_camping_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
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

# Position cursor at cell F17 (first Total Quantity cell)
echo "Positioning cursor at food items table..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Navigate to F17 (Total Quantity for Rice)
safe_xdotool ga :1 key ctrl+g
sleep 0.5
safe_xdotool ga :1 type "F17"
sleep 0.3
safe_xdotool ga :1 key Return
sleep 0.3

echo "=== Camping Food Planner Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. CALCULATE TOTAL QUANTITIES (Column F, rows 17-24)"
echo "   Formula: (Eaters_Count × Servings_per_day × 5_days × 1.1)"
echo "   Example for Rice (F17): =E17*D17*B3*F3"
echo ""
echo "2. CALCULATE TOTAL COSTS (Column G, rows 17-24)"
echo "   Formula: Total_Quantity × Unit_Cost"
echo "   Example (G17): =F17*C17"
echo ""
echo "3. CREATE SHOPPING LIST (Rows 29-36)"
echo "   Copy item names and reference calculated quantities/costs"
echo ""
echo "4. CALCULATE COST PER PERSON (Rows 40-46)"
echo "   Each person pays for items they consume"
echo "   Sum should equal total food cost"
echo ""
echo "💡 TIP: Vegetarians (Beth, Dana, Greg) don't eat Chicken"
echo "💡 TIP: Gluten-free (Chris, Dana) don't eat Pasta"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"