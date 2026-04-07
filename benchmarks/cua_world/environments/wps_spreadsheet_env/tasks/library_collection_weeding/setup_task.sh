#!/bin/bash
echo "=== Setting up library_collection_weeding task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

INVENTORY_FILE="/home/ga/Documents/library_inventory.xlsx"
rm -f "$INVENTORY_FILE" 2>/dev/null || true

# Generate realistic library dataset using Python
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

# Realistic book data seeds
authors_titles = [
    ("J.K. Rowling", "Harry Potter and the Sorcerer's Stone"),
    ("George Orwell", "1984"),
    ("Jane Austen", "Pride and Prejudice"),
    ("F. Scott Fitzgerald", "The Great Gatsby"),
    ("J.R.R. Tolkien", "The Hobbit"),
    ("Harper Lee", "To Kill a Mockingbird"),
    ("Ray Bradbury", "Fahrenheit 451"),
    ("Suzanne Collins", "The Hunger Games"),
    ("Markus Zusak", "The Book Thief"),
    ("Stephen King", "The Shining"),
    ("Agatha Christie", "And Then There Were None"),
    ("Dan Brown", "The Da Vinci Code"),
    ("John Grisham", "The Firm"),
    ("Michael Crichton", "Jurassic Park"),
    ("Neil Gaiman", "American Gods"),
    ("Margaret Atwood", "The Handmaid's Tale"),
    ("Andy Weir", "The Martian"),
    ("Gillian Flynn", "Gone Girl"),
    ("Paula Hawkins", "The Girl on the Train"),
    ("Donna Tartt", "The Goldfinch")
]

wb = Workbook()
ws = wb.active
ws.title = "Inventory"

# Headers
headers = ["BibNum", "Title", "Author", "PublicationYear", "ItemCount", "Checkouts"]
ws.append(headers)

# Format header
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color="4F81BD", end_color="4F81BD", fill_type="solid")
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill

# Generate 500 rows of data
random.seed(42) # For reproducibility
for i in range(1, 501):
    author, base_title = random.choice(authors_titles)
    # Add some variation to titles to make them unique-ish
    title = f"{base_title} (Copy {random.randint(1, 5)})" if random.random() > 0.8 else base_title
    
    bib_num = f"B{1000000 + i}"
    pub_year = random.randint(1990, 2023)
    
    # Create specific conditions to ensure we hit Weed, Order, and Keep
    rand_val = random.random()
    if rand_val < 0.15:
        # High probability of Weed: old book, few checkouts, many items
        pub_year = random.randint(1990, 2010)
        item_count = random.randint(3, 8)
        checkouts = random.randint(0, item_count * 1) # Turnover < 2
    elif rand_val < 0.30:
        # High probability of Order: popular book, few items
        item_count = random.randint(1, 2)
        checkouts = random.randint(45, 100) # Turnover > 20
    else:
        # Standard keep
        item_count = random.randint(2, 5)
        checkouts = random.randint(10, 80) # Turnover between 2 and 20

    ws.append([bib_num, title, author, pub_year, item_count, checkouts])

# Auto-adjust column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 35
ws.column_dimensions['C'].width = 20
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 12

wb.save('/home/ga/Documents/library_inventory.xlsx')
print("Created library_inventory.xlsx with 500 records.")
PYEOF

chown ga:ga "$INVENTORY_FILE" 2>/dev/null || true

# Record initial file modification time
INITIAL_MTIME=$(stat -c %Y "$INVENTORY_FILE" 2>/dev/null || echo "0")
echo "$INITIAL_MTIME" > /tmp/initial_mtime.txt

# Start WPS Spreadsheet
if ! pgrep -x "et" > /dev/null 2>&1; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$INVENTORY_FILE' &"
    
    # Wait for window
    for i in {1..15}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "library_inventory"; then
            echo "WPS window detected."
            break
        fi
        sleep 1
    done
fi

# Maximize WPS
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="