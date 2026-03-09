#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Wine Tasting Journal Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
    sudo apt-get update && sudo apt-get install -y python3-odf
fi

# Create wine journal template with headers and structure
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell, TableColumn
from odf.text import P
from odf.style import Style, TableColumnProperties, TableCellProperties, TextProperties
from odf.number import NumberStyle, Number, CurrencyStyle, CurrencySymbol, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create styles for column widths
col_style_wide = Style(name="col_wide", family="table-column")
col_style_wide.addElement(TableColumnProperties(columnwidth="1.2in"))

col_style_medium = Style(name="col_medium", family="table-column")
col_style_medium.addElement(TableColumnProperties(columnwidth="1.0in"))

col_style_notes = Style(name="col_notes", family="table-column")
col_style_notes.addElement(TableColumnProperties(columnwidth="2.5in"))

doc.automaticstyles.addElement(col_style_wide)
doc.automaticstyles.addElement(col_style_medium)
doc.automaticstyles.addElement(col_style_notes)

# Create header style (bold)
header_style = Style(name="header_style", family="table-cell")
header_style.addElement(TextProperties(fontweight="bold"))
doc.automaticstyles.addElement(header_style)

# Create currency style
currency_style = CurrencyStyle(name="currency1")
currency_style.addElement(CurrencySymbol(language="en", country="US", text="$"))
currency_style.addElement(Number(decimalplaces="2", minintegerdigits="1", grouping="true"))
doc.styles.addElement(currency_style)

cell_currency_style = Style(name="cell_currency", family="table-cell", datastylename="currency1")
doc.automaticstyles.addElement(cell_currency_style)

# Create number style for ratings (1 decimal place)
number_style = NumberStyle(name="rating1")
number_style.addElement(Number(decimalplaces="1", minintegerdigits="1"))
doc.styles.addElement(number_style)

cell_number_style = Style(name="cell_number", family="table-cell", datastylename="rating1")
doc.automaticstyles.addElement(cell_number_style)

# Add a sheet named "Wine Journal"
table = Table(name="Wine Journal")

# Add columns with proper widths
table.addElement(TableColumn(stylename=col_style_wide))  # Wine Name
table.addElement(TableColumn(stylename=col_style_medium))  # Varietal
table.addElement(TableColumn(stylename=col_style_medium))  # Rating
table.addElement(TableColumn(stylename=col_style_medium))  # Price
table.addElement(TableColumn(stylename=col_notes))  # Flavor Notes
table.addElement(TableColumn(stylename=col_style_medium))  # Recommend?

# Row 1: Headers
header_row = TableRow()
headers = ["Wine Name", "Varietal", "Rating", "Price", "Flavor Notes", "Recommend?"]
for header_text in headers:
    cell = TableCell(stylename="header_style")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Rows 2-7: Empty data rows (for 6 wines)
for _ in range(6):
    row = TableRow()
    for col_idx in range(6):
        if col_idx == 2:  # Rating column
            cell = TableCell(valuetype="float", stylename="cell_number")
        elif col_idx == 3:  # Price column
            cell = TableCell(valuetype="currency", stylename="cell_currency")
        else:
            cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Row 8: Empty separator row
empty_row = TableRow()
for _ in range(6):
    cell = TableCell()
    empty_row.addElement(cell)
table.addElement(empty_row)

# Row 9: Average labels and formulas
avg_row = TableRow()
# A9: Empty
avg_row.addElement(TableCell())
# B9: "Average Rating:"
label_cell = TableCell()
label_cell.addElement(P(text="Average Rating:"))
avg_row.addElement(label_cell)
# C9: Empty (placeholder for formula)
avg_row.addElement(TableCell(valuetype="float", stylename="cell_number"))
# D9: Empty
avg_row.addElement(TableCell())
# E9: Empty
avg_row.addElement(TableCell())
# F9: Empty
avg_row.addElement(TableCell())
table.addElement(avg_row)

# Row 10: Average price label
avg_price_row = TableRow()
# A10: Empty
avg_price_row.addElement(TableCell())
# B10: "Average Price:"
label_cell2 = TableCell()
label_cell2.addElement(P(text="Average Price:"))
avg_price_row.addElement(label_cell2)
# C10: Empty
avg_price_row.addElement(TableCell())
# D10: Empty (placeholder for formula)
avg_price_row.addElement(TableCell(valuetype="currency", stylename="cell_currency"))
# E10: Empty
avg_price_row.addElement(TableCell())
# F10: Empty
avg_price_row.addElement(TableCell())
table.addElement(avg_price_row)

# Add more empty rows for completeness
for _ in range(10):
    row = TableRow()
    for _ in range(6):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/wine_journal.ods")
print("✅ Created wine_journal.ods template successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/wine_journal.ods
sudo chmod 666 /home/ga/Documents/wine_journal.ods

# Launch LibreOffice Calc with the template
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/wine_journal.ods > /tmp/calc_wine_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_wine_task.log || true
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

# Position cursor at A2 (first data entry cell)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Wine Tasting Journal Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "You attended a wine tasting and need to organize your notes."
echo ""
echo "STEP 1: Enter the following 6 wines (rows 2-7):"
echo "  Wine 1: Château Margaux Reserve | Cabernet Sauvignon | 4.5 | \$22.00 | Rich dark fruits, oak, smooth tannins"
echo "  Wine 2: Sunrise Valley Chardonnay | Chardonnay | 3.5 | \$18.00 | Crisp apple, light citrus, buttery finish"
echo "  Wine 3: Monte Rosso Pinot | Pinot Noir | 4.2 | \$28.00 | Cherry, earthy, silky texture"
echo "  Wine 4: Desert Bloom Rosé | Rosé | 3.8 | \$15.00 | Strawberry, refreshing, dry"
echo "  Wine 5: Vintage Creek Merlot | Merlot | 4.3 | \$24.00 | Plum, chocolate, velvety"
echo "  Wine 6: Hillside Sauvignon Blanc | Sauvignon Blanc | 3.2 | \$16.00 | Grassy, tart, mineral"
echo ""
echo "STEP 2: Calculate averages:"
echo "  Cell C9: =AVERAGE(C2:C7)  [Average Rating]"
echo "  Cell D9: =AVERAGE(D2:D7)  [Average Price]"
echo ""
echo "STEP 3: Create recommendation formulas (F2:F7):"
echo "  Cell F2: =IF(AND(C2>=4.0, D2<=25), \"YES\", \"NO\")"
echo "  Copy this formula to F3:F7"
echo ""
echo "STEP 4: Apply conditional formatting:"
echo "  Select A2:F7 → Format → Conditional Formatting"
echo "  Condition: Formula is \$F2=\"YES\""
echo "  Apply green/yellow background color"
echo ""
echo "Expected recommendations: Château Margaux (YES), Vintage Creek (YES)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"