#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Meal Prep Consolidator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create ODS file with Recipes, Pantry, and Shopping List sheets
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# ===== Sheet 1: Recipes =====
recipes_table = Table(name="Recipes")

# Header row
header_row = TableRow()
for header in ["Recipe Name", "Ingredient", "Quantity", "Unit"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
recipes_table.addElement(header_row)

# Recipe data (5 recipes with overlapping ingredients)
recipes_data = [
    ["Chicken Stir Fry", "chicken breast", "2", "lbs"],
    ["Chicken Stir Fry", "olive oil", "2", "tbsp"],
    ["Chicken Stir Fry", "onion", "1", "whole"],
    ["Chicken Stir Fry", "garlic", "2", "cloves"],
    ["Chicken Stir Fry", "bell pepper", "2", "whole"],
    ["Pasta Primavera", "olive oil", "2", "tbsp"],
    ["Pasta Primavera", "onion", "1", "whole"],
    ["Pasta Primavera", "garlic", "2", "cloves"],
    ["Pasta Primavera", "bell pepper", "1", "whole"],
    ["Pasta Primavera", "pasta", "1", "lbs"],
    ["Taco Bowl", "chicken breast", "2", "lbs"],
    ["Taco Bowl", "onion", "2", "whole"],
    ["Taco Bowl", "bell pepper", "1", "whole"],
    ["Taco Bowl", "black beans", "2", "cans"],
    ["Taco Bowl", "rice", "2", "cups"],
    ["Breakfast Scramble", "eggs", "12", "whole"],
    ["Breakfast Scramble", "onion", "1", "whole"],
    ["Breakfast Scramble", "bell pepper", "1", "whole"],
    ["Breakfast Scramble", "cheese", "1", "cups"],
    ["Veggie Soup", "onion", "2", "whole"],
    ["Veggie Soup", "garlic", "2", "cloves"],
    ["Veggie Soup", "carrots", "4", "whole"],
    ["Veggie Soup", "celery", "4", "stalks"],
    ["Veggie Soup", "vegetable broth", "4", "cups"],
]

for recipe_row in recipes_data:
    row = TableRow()
    # Recipe name (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=recipe_row[0]))
    row.addElement(cell)
    # Ingredient (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=recipe_row[1]))
    row.addElement(cell)
    # Quantity (float)
    cell = TableCell(valuetype="float", value=recipe_row[2])
    cell.addElement(P(text=recipe_row[2]))
    row.addElement(cell)
    # Unit (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=recipe_row[3]))
    row.addElement(cell)
    recipes_table.addElement(row)

doc.spreadsheet.addElement(recipes_table)

# ===== Sheet 2: Pantry =====
pantry_table = Table(name="Pantry")

# Header row
header_row = TableRow()
for header in ["Ingredient", "Quantity on Hand", "Unit"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
pantry_table.addElement(header_row)

# Pantry inventory
pantry_data = [
    ["olive oil", "4", "tbsp"],
    ["onion", "5", "whole"],
    ["garlic", "1", "cloves"],
    ["salt", "100", "tsp"],
    ["pepper", "50", "tsp"],
    ["rice", "3", "cups"],
]

for pantry_row in pantry_data:
    row = TableRow()
    # Ingredient (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=pantry_row[0]))
    row.addElement(cell)
    # Quantity (float)
    cell = TableCell(valuetype="float", value=pantry_row[1])
    cell.addElement(P(text=pantry_row[1]))
    row.addElement(cell)
    # Unit (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=pantry_row[2]))
    row.addElement(cell)
    pantry_table.addElement(row)

doc.spreadsheet.addElement(pantry_table)

# ===== Sheet 3: Shopping List (empty template) =====
shopping_table = Table(name="Shopping List")

# Header row only
header_row = TableRow()
for header in ["Ingredient", "Quantity to Buy", "Unit"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
shopping_table.addElement(header_row)

# Add some empty rows
for _ in range(20):
    row = TableRow()
    for _ in range(3):
        cell = TableCell()
        row.addElement(cell)
    shopping_table.addElement(row)

doc.spreadsheet.addElement(shopping_table)

# Save the file
doc.save("/home/ga/Documents/meal_prep_shopping.ods")
print("✅ Created meal prep spreadsheet with Recipes, Pantry, and Shopping List sheets")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/meal_prep_shopping.ods
sudo chmod 666 /home/ga/Documents/meal_prep_shopping.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/meal_prep_shopping.ods > /tmp/calc_meal_prep.log 2>&1 &"

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

# Navigate to Shopping List sheet (right arrow twice to switch sheets)
echo "Navigating to Shopping List sheet..."
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.3
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.3

# Position cursor at A2 (first data entry cell)
safe_xdotool ga :1 key ctrl+Home
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Meal Prep Consolidator Task Setup Complete ==="
echo ""
echo "📋 Task: Create a consolidated shopping list from 5 recipes"
echo ""
echo "📚 Available Sheets:"
echo "  • Recipes: 5 meal recipes with ingredients (some duplicated)"
echo "  • Pantry: Current inventory you already have"
echo "  • Shopping List: WHERE YOU FILL IN what to buy"
echo ""
echo "🎯 Your Goal:"
echo "  1. Identify all unique ingredients across recipes"
echo "  2. Sum quantities for ingredients appearing in multiple recipes"
echo "  3. Subtract pantry inventory from needed amounts"
echo "  4. Populate Shopping List with only items to purchase (quantity > 0)"
echo ""
echo "💡 Expected Results:"
echo "  • olive oil: 4 tbsp needed, 4 on hand → DON'T buy (0 tbsp)"
echo "  • chicken breast: 4 lbs needed, 0 on hand → BUY 4 lbs"
echo "  • onion: 7 needed, 5 on hand → BUY 2"
echo "  • garlic: 6 cloves needed, 1 on hand → BUY 5 cloves"
echo ""
echo "🔧 Suggested Formulas:"
echo "  • Aggregation: =SUMIF(Recipes.B:B, \"ingredient_name\", Recipes.C:C)"
echo "  • Pantry lookup: =IFERROR(VLOOKUP(A2, Pantry.A:B, 2, FALSE), 0)"
echo "  • Need to buy: =MAX(0, TotalNeeded - OnHand)"