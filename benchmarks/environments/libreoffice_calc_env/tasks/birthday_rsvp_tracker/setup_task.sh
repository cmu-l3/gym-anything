#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Birthday RSVP Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create pre-populated RSVP tracker ODS file
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a table (sheet)
table = Table(name="RSVP Tracker")

# Helper function to create cell with value
def create_cell(value, value_type='string'):
    cell = TableCell(valuetype=value_type)
    if value_type == 'string':
        cell.addElement(P(text=str(value)))
    elif value_type == 'float':
        cell.setAttribute('value', str(value))
        cell.addElement(P(text=str(value)))
    return cell

# Header row
header_row = TableRow()
headers = ["Guest Name", "Child Name", "RSVP Status", "# Adults", "# Kids", "Dietary Notes", "Contact"]
for header in headers:
    cell = create_cell(header, 'string')
    header_row.addElement(cell)
table.addElement(header_row)

# Data rows with sample guests
guest_data = [
    ["Smith Family", "Emma", "Yes", 2, 1, "", "Email"],
    ["Johnson Family", "Jake", "Pending", 0, 0, "", "Text"],  # NEEDS UPDATE to Yes, 2, 1
    ["Davis Family", "Sarah", "Pending", 0, 0, "", "Email"],  # NEEDS UPDATE to No
    ["Williams Family", "Liam", "Yes", 2, 2, "Vegetarian", "Phone"],
    ["Brown Family", "Olivia", "Yes", 1, 1, "Nut allergy", "Email"],
    ["Garcia Family", "Noah", "No", 0, 0, "", "Email"],
    ["Martinez Family", "Ava", "Yes", 2, 1, "", "Text"],
]

for guest in guest_data:
    row = TableRow()
    for i, value in enumerate(guest):
        if i in [3, 4]:  # # Adults and # Kids columns
            cell = create_cell(value, 'float')
        else:
            cell = create_cell(value, 'string')
        row.addElement(cell)
    table.addElement(row)

# Empty row
empty_row = TableRow()
for _ in range(7):
    empty_row.addElement(create_cell("", 'string'))
table.addElement(empty_row)

# Summary section header
summary_header_row = TableRow()
summary_header_row.addElement(create_cell("=== SUMMARY SECTION ===", 'string'))
for _ in range(6):
    summary_header_row.addElement(create_cell("", 'string'))
table.addElement(summary_header_row)

# Days until party
days_row = TableRow()
days_row.addElement(create_cell("Days Until Party:", 'string'))
days_row.addElement(create_cell(5, 'float'))
for _ in range(5):
    days_row.addElement(create_cell("", 'string'))
table.addElement(days_row)

# Total Adults Attending (empty - needs formula)
adults_row = TableRow()
adults_row.addElement(create_cell("Total Adults Attending:", 'string'))
adults_row.addElement(create_cell("", 'string'))  # Empty - agent fills formula
for _ in range(5):
    adults_row.addElement(create_cell("", 'string'))
table.addElement(adults_row)

# Total Kids Attending (empty - needs formula)
kids_row = TableRow()
kids_row.addElement(create_cell("Total Kids Attending:", 'string'))
kids_row.addElement(create_cell("", 'string'))  # Empty - agent fills formula
for _ in range(5):
    kids_row.addElement(create_cell("", 'string'))
table.addElement(kids_row)

# Total Guests (empty - needs formula)
total_row = TableRow()
total_row.addElement(create_cell("Total Guests:", 'string'))
total_row.addElement(create_cell("", 'string'))  # Empty - agent fills formula
for _ in range(5):
    total_row.addElement(create_cell("", 'string'))
table.addElement(total_row)

# Pending Responses (empty - needs formula)
pending_row = TableRow()
pending_row.addElement(create_cell("Pending Responses:", 'string'))
pending_row.addElement(create_cell("", 'string'))  # Empty - agent fills formula
for _ in range(5):
    pending_row.addElement(create_cell("", 'string'))
table.addElement(pending_row)

# Add some empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(7):
        row.addElement(create_cell("", 'string'))
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/birthday_rsvp.ods")
print("✅ Created birthday_rsvp.ods successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/birthday_rsvp.ods
sudo chmod 666 /home/ga/Documents/birthday_rsvp.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/birthday_rsvp.ods > /tmp/calc_rsvp_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_rsvp_task.log || true
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Birthday RSVP Tracker Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📬 You received two RSVP updates:"
echo "   • Jake's mom texted: 'We're coming! 2 adults + Jake'"
echo "   • Sarah's parents emailed: 'Sorry, can't make it'"
echo ""
echo "✏️  UPDATE REQUIRED:"
echo "   1. Find Jake (Johnson Family, Row 3):"
echo "      - Change RSVP Status → 'Yes'"
echo "      - Change # Adults → 2"
echo "      - Change # Kids → 1"
echo ""
echo "   2. Find Sarah (Davis Family, Row 4):"
echo "      - Change RSVP Status → 'No'"
echo ""
echo "📊 CREATE FORMULAS in Summary Section (Rows 12-15):"
echo "   • Total Adults Attending: =SUMIF(C:C,\"Yes\",D:D)"
echo "   • Total Kids Attending: =SUMIF(C:C,\"Yes\",E:E)"
echo "   • Total Guests: (sum of adults + kids)"
echo "   • Pending Responses: =COUNTIF(C:C,\"Pending\")"
echo ""
echo "🎨 BONUS (Optional): Apply conditional formatting to"
echo "   RSVP Status column (Pending=Yellow, Yes=Green, No=Gray)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"