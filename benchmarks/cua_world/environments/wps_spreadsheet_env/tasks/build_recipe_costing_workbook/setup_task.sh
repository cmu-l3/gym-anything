#!/bin/bash
echo "=== Setting up build_recipe_costing_workbook task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/restaurant_recipe_costing.xlsx"
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate the initial spreadsheet
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws_prices = wb.active
ws_prices.title = 'Ingredient_Prices'

ingredients = [
    ("Ground beef", "lb", 5.45),
    ("Chicken breast", "lb", 4.11),
    ("Bacon", "lb", 7.16),
    ("Cheddar cheese", "lb", 6.15),
    ("Parmesan cheese", "lb", 9.99),
    ("Butter", "lb", 4.89),
    ("Heavy cream", "qt", 5.49),
    ("Spaghetti pasta", "lb", 1.49),
    ("All purpose flour", "lb", 0.58),
    ("White rice", "lb", 0.92),
    ("Canned tomatoes (28oz)", "can", 1.89),
    ("Canned clams", "lb", 8.99),
    ("Iceberg lettuce", "lb", 1.88),
    ("Romaine lettuce", "lb", 2.29),
    ("Tomatoes", "lb", 2.15),
    ("Onions", "lb", 1.43),
    ("Garlic", "lb", 3.50),
    ("Hamburger buns", "pack", 3.50),
    ("Croutons", "pack", 2.50),
    ("Potatoes", "lb", 0.99),
    ("Carrots", "lb", 1.15),
    ("Bell peppers", "lb", 2.45),
    ("Broccoli", "lb", 1.99),
    ("Olive oil", "qt", 8.50),
    ("Eggs", "dozen", 3.12)
]

header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9E1F2', end_color='D9E1F2', fill_type='solid')

ws_prices.append(["Ingredient", "Unit", "Price"])
for cell in ws_prices[1]:
    cell.font = header_font
    cell.fill = header_fill

for ing in ingredients:
    ws_prices.append(ing)

ws_prices.column_dimensions['A'].width = 25
ws_prices.column_dimensions['B'].width = 10
ws_prices.column_dimensions['C'].width = 12

for row in ws_prices.iter_rows(min_row=2, max_row=ws_prices.max_row, min_col=3, max_col=3):
    for cell in row:
        cell.number_format = '$#,##0.00'

ws_recipes = wb.create_sheet("Recipes")

recipes = [
    ("Classic Beef Burger", 4, [
        ("Ground beef", 1.5, "lb"),
        ("Hamburger buns", 0.5, "pack"),
        ("Cheddar cheese", 0.25, "lb"),
        ("Bacon", 0.25, "lb"),
        ("Tomatoes", 0.5, "lb"),
        ("Iceberg lettuce", 0.25, "lb"),
    ]),
    ("Caesar Salad", 6, [
        ("Romaine lettuce", 1.5, "lb"),
        ("Parmesan cheese", 0.25, "lb"),
        ("Croutons", 1, "pack"),
        ("Olive oil", 0.1, "qt"),
        ("Eggs", 0.25, "dozen"),
        ("Garlic", 0.05, "lb"),
    ]),
    ("Spaghetti Bolognese", 8, [
        ("Spaghetti pasta", 1, "lb"),
        ("Ground beef", 1, "lb"),
        ("Canned tomatoes (28oz)", 2, "can"),
        ("Onions", 0.5, "lb"),
        ("Garlic", 0.1, "lb"),
        ("Olive oil", 0.1, "qt"),
        ("Carrots", 0.5, "lb"),
        ("Parmesan cheese", 0.2, "lb"),
        ("Butter", 0.1, "lb"),
    ]),
    ("Grilled Chicken Sandwich", 4, [
        ("Chicken breast", 1.5, "lb"),
        ("Hamburger buns", 0.5, "pack"),
        ("Tomatoes", 0.5, "lb"),
        ("Iceberg lettuce", 0.25, "lb"),
        ("Bacon", 0.25, "lb"),
        ("Cheddar cheese", 0.25, "lb"),
        ("Olive oil", 0.05, "qt"),
    ]),
    ("New England Clam Chowder", 10, [
        ("Canned clams", 2, "lb"),
        ("Potatoes", 2, "lb"),
        ("Heavy cream", 1, "qt"),
        ("Bacon", 0.5, "lb"),
        ("Onions", 0.5, "lb"),
        ("Butter", 0.25, "lb"),
        ("All purpose flour", 0.25, "lb"),
        ("Garlic", 0.05, "lb"),
    ]),
    ("Garden Vegetable Stir-Fry", 4, [
        ("Broccoli", 1, "lb"),
        ("Bell peppers", 0.5, "lb"),
        ("Carrots", 0.5, "lb"),
        ("Onions", 0.5, "lb"),
        ("White rice", 1, "lb"),
        ("Olive oil", 0.1, "qt"),
        ("Garlic", 0.05, "lb"),
        ("Chicken breast", 0.5, "lb"),
        ("Eggs", 0.16, "dozen"),
    ])
]

ws_recipes.column_dimensions['A'].width = 30
ws_recipes.column_dimensions['B'].width = 12
ws_recipes.column_dimensions['C'].width = 10
ws_recipes.column_dimensions['D'].width = 15
ws_recipes.column_dimensions['E'].width = 15

row_idx = 1
for name, yield_val, ings in recipes:
    ws_recipes.cell(row=row_idx, column=1, value=name).font = Font(bold=True, size=12)
    ws_recipes.cell(row=row_idx, column=3, value="Yield:").font = Font(bold=True)
    ws_recipes.cell(row=row_idx, column=4, value=yield_val)
    row_idx += 1
    
    headers = ["Ingredient", "Quantity", "Unit", "Unit Cost", "Extended Cost"]
    for col, h in enumerate(headers, 1):
        cell = ws_recipes.cell(row=row_idx, column=col, value=h)
        cell.font = header_font
        cell.fill = header_fill
    row_idx += 1
    
    for ing in ings:
        ws_recipes.cell(row=row_idx, column=1, value=ing[0])
        ws_recipes.cell(row=row_idx, column=2, value=ing[1])
        ws_recipes.cell(row=row_idx, column=3, value=ing[2])
        row_idx += 1
        
    ws_recipes.cell(row=row_idx, column=4, value="Total Cost:").font = Font(bold=True)
    ws_recipes.cell(row=row_idx, column=4).alignment = Alignment(horizontal='right')
    row_idx += 1
    
    ws_recipes.cell(row=row_idx, column=4, value="Cost Per Serving:").font = Font(bold=True)
    ws_recipes.cell(row=row_idx, column=4).alignment = Alignment(horizontal='right')
    row_idx += 2

wb.save('/home/ga/Documents/restaurant_recipe_costing.xlsx')
PYEOF

chown ga:ga "$FILE_PATH" 2>/dev/null || true

# Ensure no running WPS instances
pkill -x et 2>/dev/null || true
pkill -f "wps" 2>/dev/null || true
sleep 1

# Start WPS Spreadsheet
su - ga -c "DISPLAY=:1 et '$FILE_PATH' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "restaurant_recipe_costing"; then
        break
    fi
    sleep 1
done

# Focus and maximize
DISPLAY=:1 wmctrl -r "restaurant_recipe_costing" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "restaurant_recipe_costing" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="