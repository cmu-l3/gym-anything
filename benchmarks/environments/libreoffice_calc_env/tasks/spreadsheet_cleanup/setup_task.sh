#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Spreadsheet Cleanup Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create the messy ODS file with junk rows, narrow columns, and unformatted headers
echo "Creating messy spreadsheet file..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell, TableColumn
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties, ParagraphProperties
from odf import number
import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a narrow column style (default width)
narrow_col_style = Style(name="NarrowCol", family="table-column")
narrow_col_style.addElement(TableColumnProperties(columnwidth="0.7in"))  # Narrow ~64px
doc.automaticstyles.addElement(narrow_col_style)

# Create sheet
table = Table(name="Sheet1")

# Add narrow columns (5 columns)
for i in range(5):
    col = TableColumn(stylename=narrow_col_style, defaultcellstylename="Default")
    table.addElement(col)

# Helper function to add a row with text
def add_text_row(values):
    row = TableRow()
    for val in values:
        cell = TableCell()
        if val:
            p = P(text=str(val))
            cell.addElement(p)
        row.addElement(cell)
    return row

# Row 1: Blank
table.addElement(add_text_row(["", "", "", "", ""]))

# Row 2: Export metadata
table.addElement(add_text_row(["Exported from FormSubmit Pro on 2024-01-15", "", "", "", ""]))

# Row 3: Blank
table.addElement(add_text_row(["", "", "", "", ""]))

# Row 4: Summary
table.addElement(add_text_row(["Total Registrations: 46", "", "", "", ""]))

# Row 5: Headers (plain text, not bold)
headers = ["Name", "Email", "Registration Date", "Ticket Type", "Dietary Restrictions"]
table.addElement(add_text_row(headers))

# Sample data for 46 attendees
first_names = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry", "Iris", "Jack",
               "Kate", "Leo", "Maya", "Noah", "Olivia", "Paul", "Quinn", "Rachel", "Sam", "Tara",
               "Uma", "Victor", "Wendy", "Xavier", "Yara", "Zack", "Amy", "Ben", "Claire", "Dan",
               "Emma", "Felix", "Gina", "Hugo", "Ivy", "James", "Kara", "Luke", "Mia", "Nick",
               "Oscar", "Piper", "Quincy", "Rosa", "Steve", "Tina"]

last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez",
              "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
              "Lee", "Perez", "Thompson", "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson",
              "Walker", "Young", "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores",
              "Green", "Adams", "Nelson", "Baker", "Hall", "Rivera"]

ticket_types = ["General Admission", "VIP", "Early Bird", "Student", "Group"]
dietary = ["None", "Vegetarian", "Vegan", "Gluten-Free", "Nut Allergy", "Dairy-Free", "Kosher", "Halal"]

# Generate 46 data rows (rows 6-51)
for i in range(46):
    name = f"{first_names[i]} {last_names[i]}"
    email = f"{first_names[i].lower()}.{last_names[i].lower()}@email.com"
    
    # Dates in January 2024
    day = (i % 28) + 1
    date = f"2024-01-{day:02d}"
    
    ticket = ticket_types[i % len(ticket_types)]
    diet = dietary[i % len(dietary)]
    
    table.addElement(add_text_row([name, email, date, ticket, diet]))

doc.spreadsheet.addElement(table)

# Save
output_path = "/home/ga/Documents/event_registrations_messy.ods"
doc.save(output_path)
print(f"✅ Created messy spreadsheet: {output_path}")
print(f"   - 4 junk rows at top")
print(f"   - Headers in row 5 (not bold)")
print(f"   - Narrow columns causing truncation")
print(f"   - No freeze panes")
print(f"   - 46 data rows")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/event_registrations_messy.ods
sudo chmod 666 /home/ga/Documents/event_registrations_messy.ods

# Verify file was created
if [ ! -f "/home/ga/Documents/event_registrations_messy.ods" ]; then
    echo "ERROR: Failed to create messy ODS file"
    exit 1
fi

echo "✅ Messy spreadsheet created successfully"
ls -lh /home/ga/Documents/event_registrations_messy.ods

# Launch LibreOffice Calc with the messy spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/event_registrations_messy.ods > /tmp/calc_cleanup_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_cleanup_task.log || true
    exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window
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

echo "=== Spreadsheet Cleanup Task Setup Complete ==="
echo ""
echo "📋 TASK: Clean up the messy event registration spreadsheet"
echo ""
echo "Current Problems:"
echo "  ❌ Junk rows at top (rows 1-4)"
echo "  ❌ Headers buried in row 5"
echo "  ❌ Headers not bold"
echo "  ❌ Narrow columns with text truncation"
echo "  ❌ No freeze panes"
echo ""
echo "Required Actions:"
echo "  1. Delete rows 1-4 (select rows, right-click, Delete Rows)"
echo "  2. Bold the header row (select row 1, Ctrl+B)"
echo "  3. Auto-fit columns (Format → Columns → Optimal Width)"
echo "  4. Freeze header row (click A2, View → Freeze Rows and Columns)"
echo "  5. Save the file"
echo ""