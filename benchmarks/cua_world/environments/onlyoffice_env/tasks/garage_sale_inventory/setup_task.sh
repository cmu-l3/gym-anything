#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Garage Sale Inventory Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with messy garage sale data
SHEET_PATH="$WORKSPACE_DIR/garage_sale_items.xlsx"

cat > /tmp/create_garage_sale.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys
import random

wb = Workbook()
ws = wb.active
ws.title = "Garage Sale"

# Add headers
ws['A1'] = "Item Description"
ws['B1'] = "Category"
ws['C1'] = "Asking Price"
ws['D1'] = ""  # Will become "Minimum Price"

# Realistic garage sale items with messy data
# Format: (description, category, price) - None means missing
items = [
    ("IKEA coffee table, minor scratches", "Furniture", 25),
    ("Set of 4 dining chairs", "furniture", 40),
    ("Kids bicycle with training wheels", None, 15),
    ("Food processor, never used", "Kitchen", None),
    ("Box of romance novels (~20 books)", "Books", 5),
    ("Vintage brass desk lamp", None, None),
    ("Yoga mat and foam blocks", "Sporting Goods", 8),
    ("Electric drill with bits", "Tools", 30),
    ("Wooden bookshelf, 5 shelves", "Furniture", 35),
    ("Slow cooker, 6 quart", "Kitchen items", 12),
    ("Men's winter coat, size L", "Clothing", 15),
    ("Board game collection (8 games)", "Toys", None),
    ("Decorative wall mirrors (set of 3)", "Home Decor", 20),
    ("Laptop bag, leather", None, 10),
    ("Garden hand tools set", "Tools", None),
    ("Toaster oven, works perfectly", "Kitchen", 18),
    ("Kids' puzzles and coloring books", "Toys", 5),
    ("Framed artwork prints (4 pieces)", "Home Decor", None),
    ("Women's boots, size 8", "Clothing", 12),
    ("Bluetooth speaker, good condition", "Electronics", None),
    ("Desk organizer and file holder", "Miscellaneous", 8),
    ("Camping sleeping bag", "Sporting Goods", None),
    ("Pressure cooker, barely used", "Kitchen Stuff", 25),
    ("Table lamp with shade", "Home Decor", 15),
    ("Hardcover fiction books (12 books)", "Books", None),
    ("Folding step ladder", "Tools", 20),
    ("Kids' plastic storage bins (6 bins)", None, 6),
    ("Decorative throw pillows (5)", "Home Decor", None),
    ("Digital alarm clock radio", "Electronics", 8),
    ("Stainless steel pots and pans set", "kitchen items", 30),
    ("Badminton set with net", "Sporting Goods", 15),
    ("Office desk chair, adjustable", "Furniture", None),
    ("Blender with multiple speeds", "Kitchen", 15),
    ("Kids' toy cars and trucks (lot)", "Toys", 10),
    ("Wall-mounted coat rack", None, 12),
    ("Electric kettle, 1.7L", "Kitchen", None),
    ("Paperback book collection (~30)", "Books", 8),
    ("Tennis rackets (2) with case", "Sporting Goods", None),
    ("Ceramic flower vases (3 sizes)", "Home Decor", 10),
    ("Portable fan, 3 speeds", "Electronics", 12),
    ("Wrench and socket set", "Tools", None),
    ("Kids' building blocks (large set)", "Toys", 15),
    ("Microwave cart on wheels", "furniture", 20),
    ("Kitchen utensil set", "Kitchen", 8),
    ("Decorative candles and holders", "Miscellaneous", None)
]

# Populate the spreadsheet with messy data
for i, (description, category, price) in enumerate(items, start=2):
    ws[f'A{i}'] = description
    
    # Category: some missing, inconsistent capitalization
    if category is not None:
        ws[f'B{i}'] = category
    # else leave blank
    
    # Price: some missing
    if price is not None:
        ws[f'C{i}'] = price
    # else leave blank

# Column D is intentionally left empty for agent to add "Minimum Price"

wb.save(sys.argv[1])
print(f"Garage sale spreadsheet created: {sys.argv[1]}")
print(f"Total items: {len(items)}")
print(f"Missing prices: {sum(1 for _, _, p in items if p is None)}")
print(f"Missing categories: {sum(1 for _, c, _ in items if c is None)}")
PYEOF

chmod +x /tmp/create_garage_sale.py
python3 /tmp/create_garage_sale.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Garage sale spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_garage_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_garage_task.log || true
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

echo "=== Garage Sale Inventory Task Setup Complete ==="
echo ""
echo "📝 SCENARIO: You're preparing for a neighborhood garage sale this Saturday."
echo "   Your spreadsheet has ~45 items but the data is incomplete and messy!"
echo ""
echo "🎯 YOUR TASKS:"
echo "  1. Fill in MISSING PRICES for items without one (estimate reasonably: $1-50)"
echo "  2. Fill in MISSING CATEGORIES and standardize them"
echo "     (Use: Furniture, Kitchen, Electronics, Clothing, Toys, Books,"
echo "           Home Decor, Sporting Goods, Tools, Miscellaneous)"
echo "  3. Add 'Minimum Price' header in Column D"
echo "  4. Create FORMULAS in Column D to calculate 75% of asking price"
echo "  5. Create a SUMMARY SECTION with formulas for:"
echo "     - Total Potential Revenue (SUM of asking prices)"
echo "     - Minimum Acceptable Revenue (SUM of minimum prices)"
echo "     - Item Count (COUNT of items)"
echo "     - Average Item Price (AVERAGE of asking prices)"
echo "  6. SORT data by Category (alphabetically), then Price (high to low)"
echo "  7. Make HEADERS BOLD for easy reading"
echo "  8. SAVE the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: The garage sale is Saturday - you need this done today!"
echo ""