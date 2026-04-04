#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Board Game Value Analyzer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create board game collection ODS file with proper structure
# Install odfpy if not already available
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create the ODS file with board game data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, Number, CurrencyStyle, CurrencySymbol, Text as NumText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create styles for currency and date
currency_style = CurrencyStyle(name="currency1")
currency_style.addElement(CurrencySymbol(language="en", country="US", text="$"))
currency_style.addElement(Number(decimalplaces="2", minintegerdigits="1", grouping="true"))
doc.styles.addElement(currency_style)

# Create table
table = Table(name="Sheet1")

# Header row
header_row = TableRow()
headers = ["Game Name", "Purchase Price", "Play Count", "Rating", "Last Played"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Data rows - board game collection
# Format: [Game Name, Cost, Plays, Rating, Last Played]
# Ratings: some are 1-5 scale (Catan, Pandemic, Azul, Splendor, Monopoly)
#          others are 1-10 scale (Wingspan, Ticket to Ride, Unmatched, 7 Wonders)
data_rows = [
    ["Wingspan", 40, 12, 9, "2024-11-15"],
    ["Catan", 30, 15, 4, "2024-12-20"],
    ["Pandemic Legacy", 70, 8, 5, "2024-10-30"],
    ["Monopoly", 20, 2, 2, "2023-01-05"],
    ["Gloomhaven", 140, 0, None, ""],
    ["Ticket to Ride", 35, 24, 8, "2024-12-28"],
    ["Azul", 30, 18, 4, "2024-11-22"],
    ["Unmatched", 25, 7, 7, "2024-09-14"],
    ["Splendor", 30, 11, 4, "2024-12-01"],
    ["7 Wonders", 45, 3, 3, "2022-06-10"],
]

for row_data in data_rows:
    row = TableRow()
    
    # Game name (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=row_data[0]))
    row.addElement(cell)
    
    # Purchase price (float)
    cell = TableCell(valuetype="float", value=str(row_data[1]))
    cell.addElement(P(text=f"${row_data[1]}"))
    row.addElement(cell)
    
    # Play count (float)
    cell = TableCell(valuetype="float", value=str(row_data[2]))
    cell.addElement(P(text=str(row_data[2])))
    row.addElement(cell)
    
    # Rating (float or empty)
    if row_data[3] is not None:
        cell = TableCell(valuetype="float", value=str(row_data[3]))
        cell.addElement(P(text=str(row_data[3])))
    else:
        cell = TableCell()
    row.addElement(cell)
    
    # Last played date (string)
    cell = TableCell(valuetype="string")
    if row_data[4]:
        cell.addElement(P(text=row_data[4]))
    row.addElement(cell)
    
    table.addElement(row)

# Add empty rows for formula columns
for row in table.getElementsByType(TableRow):
    for _ in range(3):  # Add 3 empty columns (F, G, H)
        cell = TableCell()
        row.addElement(cell)

doc.spreadsheet.addElement(table)

# Save the file
output_path = "/home/ga/Documents/board_game_collection.ods"
doc.save(output_path)
print(f"Created board game collection ODS file: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/board_game_collection.ods
sudo chmod 666 /home/ga/Documents/board_game_collection.ods

echo "✅ Created board_game_collection.ods with 10 games"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/board_game_collection.ods > /tmp/calc_boardgame.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_boardgame.log || true
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

# Position cursor at F1 (first formula column)
echo "Positioning cursor at F1..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right Right
sleep 0.2

echo "=== Board Game Value Analyzer Task Setup Complete ==="
echo ""
echo "📊 Board Game Collection Data Loaded"
echo "📝 Task Instructions:"
echo "  1. Add 'Cost Per Play' header in F1"
echo "  2. In F2, create formula: =IF(C2>0, B2/C2, B2)"
echo "  3. Copy formula down F2:F11"
echo "  4. Add 'Normalized Rating' header in G1"
echo "  5. In G2, create formula: =IF(ISBLANK(D2), 0, IF(D2<=5, (D2-1)/4, (D2-1)/9))"
echo "  6. Copy formula down G2:G11"
echo "  7. Add 'Value Score' header in H1"
echo "  8. In H2, create formula: =IF(F2>0, G2/(F2/100), 0)"
echo "  9. Copy formula down H2:H11"
echo ""
echo "💡 Key Points:"
echo "  - Handle zero plays (avoid #DIV/0!)"
echo "  - Normalize ratings: 1-5 scale uses /4, 1-10 scale uses /9"
echo "  - Gloomhaven has 0 plays and blank rating"
echo "  - Value score: higher = better entertainment value"