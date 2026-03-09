#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Tool Library Damage Detective Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Calculate dates for realistic borrowing log
# T-047 last checkout: 9 days ago, returned today
TODAY=$(date +%Y-%m-%d)
NINE_DAYS_AGO=$(date -d "9 days ago" +%Y-%m-%d)
FIFTEEN_DAYS_AGO=$(date -d "15 days ago" +%Y-%m-%d)
THIRTY_DAYS_AGO=$(date -d "30 days ago" +%Y-%m-%d)
SIXTY_DAYS_AGO=$(date -d "60 days ago" +%Y-%m-%d)

# Create multi-sheet ODS file using Python
python3 << PYEOF
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from datetime import datetime, timedelta

print("Creating tool library workbook...")

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# ===== SHEET 1: Inventory =====
inventory_table = Table(name="Inventory")

# Header row
header_row = TableRow()
headers = ["ToolID", "ToolName", "Category", "Condition", "PurchaseDate", "Available"]
for h in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=h))
    header_row.addElement(cell)
inventory_table.addElement(header_row)

# Sample tool inventory (30 tools)
tools = [
    ["T-001", "Cordless Drill", "Power Tools", "Good", "2019-05-10", "Yes"],
    ["T-002", "Circular Saw", "Power Tools", "Good", "2019-06-15", "Yes"],
    ["T-003", "Chainsaw", "Yard", "Fair", "2020-01-20", "Yes"],
    ["T-004", "Ladder 20ft", "General", "Good", "2018-03-12", "Yes"],
    ["T-005", "Tile Saw", "Power Tools", "Good", "2020-08-05", "No"],
    ["T-006", "Hedge Trimmer", "Yard", "Good", "2021-02-18", "Yes"],
    ["T-007", "Paint Sprayer", "Painting", "Good", "2019-11-22", "Yes"],
    ["T-008", "Pressure Washer", "Cleaning", "Good", "2020-04-30", "Yes"],
    ["T-009", "Shop Vac", "Cleaning", "Fair", "2018-07-08", "Yes"],
    ["T-010", "Orbital Sander", "Power Tools", "Good", "2021-01-14", "Yes"],
    ["T-047", "Post Hole Digger", "Yard", "Good", "2021-03-15", "Yes"],  # THE DAMAGED TOOL
    ["T-012", "Lawn Aerator", "Yard", "Good", "2020-05-20", "Yes"],
    ["T-013", "Concrete Mixer", "Construction", "Fair", "2019-09-10", "Yes"],
    ["T-014", "Reciprocating Saw", "Power Tools", "Good", "2020-11-02", "Yes"],
    ["T-015", "Miter Saw", "Power Tools", "Good", "2021-06-18", "No"],
    ["T-016", "Belt Sander", "Power Tools", "Good", "2020-02-25", "Yes"],
    ["T-017", "Pole Saw", "Yard", "Fair", "2019-08-14", "Yes"],
    ["T-018", "Floor Nailer", "Flooring", "Good", "2021-04-22", "Yes"],
    ["T-019", "Carpet Cleaner", "Cleaning", "Good", "2020-07-30", "Yes"],
    ["T-020", "Drywall Lift", "Construction", "Good", "2019-12-05", "Yes"],
    ["T-021", "Stud Finder", "General", "Good", "2021-01-08", "Yes"],
    ["T-022", "Drain Snake", "Plumbing", "Good", "2020-03-17", "Yes"],
    ["T-023", "Jigsaw", "Power Tools", "Good", "2019-10-20", "Yes"],
    ["T-024", "Hand Truck", "General", "Fair", "2018-11-12", "Yes"],
    ["T-025", "Extension Ladder", "General", "Good", "2020-06-08", "Yes"],
    ["T-026", "Leaf Blower", "Yard", "Good", "2021-09-15", "Yes"],
    ["T-027", "Wood Chipper", "Yard", "Good", "2020-10-22", "Yes"],
    ["T-028", "Planer", "Power Tools", "Fair", "2019-07-18", "Yes"],
    ["T-029", "Router", "Power Tools", "Good", "2021-02-11", "Yes"],
    ["T-030", "Impact Driver", "Power Tools", "Good", "2020-12-20", "Yes"],
]

for tool in tools:
    row = TableRow()
    for i, value in enumerate(tool):
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    inventory_table.addElement(row)

doc.spreadsheet.addElement(inventory_table)

# ===== SHEET 2: BorrowingLog =====
borrowing_table = Table(name="BorrowingLog")

# Header row
header_row = TableRow()
headers = ["LogID", "ToolID", "MemberID", "CheckoutDate", "ReturnDate", "ConditionOut", "ConditionBack"]
for h in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=h))
    header_row.addElement(cell)
borrowing_table.addElement(header_row)

# Sample borrowing records (50+ entries, including multiple for T-047)
# Calculate dynamic dates
today = "${TODAY}"
nine_days_ago = "${NINE_DAYS_AGO}"
fifteen_days_ago = "${FIFTEEN_DAYS_AGO}"
thirty_days_ago = "${THIRTY_DAYS_AGO}"
sixty_days_ago = "${SIXTY_DAYS_AGO}"

borrowings = [
    ["L-001", "T-001", "M-005", "2024-01-10", "2024-01-15", "Good", "Good"],
    ["L-002", "T-003", "M-012", "2024-01-12", "2024-01-18", "Fair", "Fair"],
    ["L-003", "T-008", "M-003", "2024-01-15", "2024-01-20", "Good", "Good"],
    ["L-004", "T-047", "M-007", "2024-01-20", "2024-01-25", "Good", "Good"],  # T-047 history 1
    ["L-005", "T-002", "M-015", "2024-01-22", "2024-01-28", "Good", "Good"],
    ["L-006", "T-006", "M-019", "2024-01-25", "2024-01-30", "Good", "Good"],
    ["L-007", "T-012", "M-008", "2024-02-01", "2024-02-05", "Good", "Good"],
    ["L-008", "T-004", "M-011", "2024-02-03", "2024-02-09", "Good", "Good"],
    ["L-009", "T-047", "M-014", "2024-02-05", "2024-02-11", "Good", "Good"],  # T-047 history 2
    ["L-010", "T-010", "M-002", "2024-02-08", "2024-02-13", "Good", "Good"],
    ["L-011", "T-013", "M-006", "2024-02-10", "2024-02-16", "Fair", "Fair"],
    ["L-012", "T-007", "M-020", "2024-02-12", "2024-02-17", "Good", "Good"],
    ["L-013", "T-001", "M-009", "2024-02-15", "2024-02-20", "Good", "Good"],
    ["L-014", "T-018", "M-013", "2024-02-18", "2024-02-24", "Good", "Good"],
    ["L-015", "T-022", "M-004", "2024-02-20", "2024-02-25", "Good", "Good"],
    ["L-016", "T-047", "M-001", "2024-02-22", "2024-02-28", "Good", "Good"],  # T-047 history 3
    ["L-017", "T-003", "M-017", "2024-02-25", "2024-03-02", "Fair", "Fair"],
    ["L-018", "T-025", "M-010", "2024-02-28", "2024-03-05", "Good", "Good"],
    ["L-019", "T-008", "M-016", "2024-03-01", "2024-03-06", "Good", "Good"],
    ["L-020", "T-014", "M-007", "2024-03-03", "2024-03-09", "Good", "Good"],
    ["L-021", "T-006", "M-012", "2024-03-05", "2024-03-10", "Good", "Good"],
    ["L-022", "T-019", "M-018", "2024-03-08", "2024-03-14", "Good", "Good"],
    ["L-023", "T-002", "M-003", "2024-03-10", "2024-03-16", "Good", "Good"],
    ["L-024", "T-026", "M-015", "2024-03-12", "2024-03-18", "Good", "Good"],
    ["L-025", "T-047", "M-019", "2024-03-15", "2024-03-20", "Good", "Good"],  # T-047 history 4
    ["L-026", "T-011", "M-005", "2024-03-18", "2024-03-23", "Good", "Good"],
    ["L-027", "T-004", "M-011", "2024-03-20", "2024-03-26", "Good", "Good"],
    ["L-028", "T-016", "M-008", "2024-03-22", "2024-03-28", "Good", "Good"],
    ["L-029", "T-021", "M-002", "2024-03-25", "2024-03-30", "Good", "Good"],
    ["L-030", "T-001", "M-014", "2024-03-28", "2024-04-02", "Good", "Good"],
    ["L-031", "T-023", "M-006", "2024-04-01", "2024-04-06", "Good", "Good"],
    ["L-032", "T-008", "M-020", "2024-04-03", "2024-04-08", "Good", "Good"],
    ["L-033", "T-027", "M-009", "2024-04-05", "2024-04-11", "Good", "Good"],
    ["L-034", "T-013", "M-013", "2024-04-08", "2024-04-14", "Fair", "Fair"],
    ["L-035", "T-003", "M-004", "2024-04-10", "2024-04-16", "Fair", "Fair"],
    ["L-036", "T-029", "M-001", "2024-04-12", "2024-04-17", "Good", "Good"],
    ["L-037", "T-007", "M-017", "2024-04-15", "2024-04-20", "Good", "Good"],
    ["L-038", "T-018", "M-010", "2024-04-18", "2024-04-24", "Good", "Good"],
    ["L-039", "T-010", "M-016", "2024-04-20", "2024-04-25", "Good", "Good"],
    ["L-040", "T-006", "M-007", "2024-04-22", "2024-04-28", "Good", "Good"],
    ["L-041", "T-030", "M-012", "2024-04-25", "2024-04-30", "Good", "Good"],
    ["L-042", "T-002", "M-018", "2024-04-28", "2024-05-03", "Good", "Good"],
    ["L-043", "T-024", "M-003", "2024-05-01", "2024-05-06", "Fair", "Fair"],
    ["L-044", "T-014", "M-015", "2024-05-03", "2024-05-08", "Good", "Good"],
    ["L-045", "T-019", "M-019", "2024-05-05", "2024-05-10", "Good", "Good"],
    ["L-046", "T-001", "M-005", "2024-05-08", "2024-05-13", "Good", "Good"],
    ["L-047", "T-025", "M-011", "2024-05-10", "2024-05-16", "Good", "Good"],
    ["L-048", "T-008", "M-008", "2024-05-12", "2024-05-17", "Good", "Good"],
    # THE CRITICAL ENTRY - Last borrower of T-047 (M-023, 9 days ago to today)
    ["L-089", "T-047", "M-023", nine_days_ago, today, "Good", "Damaged"],
]

for borrowing in borrowings:
    row = TableRow()
    for value in borrowing:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    borrowing_table.addElement(row)

doc.spreadsheet.addElement(borrowing_table)

# ===== SHEET 3: Members =====
members_table = Table(name="Members")

# Header row
header_row = TableRow()
headers = ["MemberID", "Name", "Email", "Phone", "JoinDate", "GoodStanding", "PendingContact"]
for h in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=h))
    header_row.addElement(cell)
members_table.addElement(header_row)

# Sample members (20 members)
members = [
    ["M-001", "John Martinez", "john.martinez@email.com", "555-0101", "2021-06-15", "Yes", ""],
    ["M-002", "Emily Davis", "emily.davis@email.com", "555-0102", "2021-08-22", "Yes", ""],
    ["M-003", "Michael Brown", "michael.brown@email.com", "555-0103", "2021-09-10", "Yes", ""],
    ["M-004", "Jessica Wilson", "jessica.wilson@email.com", "555-0104", "2021-10-05", "Yes", ""],
    ["M-005", "David Anderson", "david.anderson@email.com", "555-0105", "2021-11-18", "Yes", ""],
    ["M-006", "Sarah Thompson", "sarah.thompson@email.com", "555-0106", "2021-12-02", "Yes", ""],
    ["M-007", "Robert Garcia", "robert.garcia@email.com", "555-0107", "2022-01-14", "Yes", ""],
    ["M-008", "Jennifer Lee", "jennifer.lee@email.com", "555-0108", "2022-02-20", "Yes", ""],
    ["M-009", "Christopher White", "chris.white@email.com", "555-0109", "2022-03-08", "Yes", ""],
    ["M-010", "Amanda Harris", "amanda.harris@email.com", "555-0110", "2022-04-12", "Yes", ""],
    ["M-011", "Daniel Clark", "daniel.clark@email.com", "555-0111", "2022-05-25", "Yes", ""],
    ["M-012", "Michelle Rodriguez", "michelle.r@email.com", "555-0112", "2022-06-30", "Yes", ""],
    ["M-013", "James Lewis", "james.lewis@email.com", "555-0113", "2022-07-18", "Yes", ""],
    ["M-014", "Lisa Walker", "lisa.walker@email.com", "555-0114", "2022-08-22", "Yes", ""],
    ["M-015", "Kevin Hall", "kevin.hall@email.com", "555-0115", "2022-09-10", "Yes", ""],
    ["M-016", "Laura Allen", "laura.allen@email.com", "555-0116", "2022-10-05", "Yes", ""],
    ["M-017", "Brian Young", "brian.young@email.com", "555-0117", "2022-11-14", "Yes", ""],
    ["M-018", "Rebecca King", "rebecca.king@email.com", "555-0118", "2022-12-01", "Yes", ""],
    ["M-019", "Steven Wright", "steven.wright@email.com", "555-0119", "2023-01-20", "Yes", ""],
    ["M-023", "Sarah Chen", "sarah.chen@email.com", "555-0123", "2022-01-10", "Yes", ""],  # THE CULPRIT
]

for member in members:
    row = TableRow()
    for value in member:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    members_table.addElement(row)

doc.spreadsheet.addElement(members_table)

# Save the file
output_path = "/home/ga/Documents/tool_library.ods"
doc.save(output_path)
print(f"✅ Created tool library workbook: {output_path}")
print(f"   - Sheets: Inventory, BorrowingLog, Members")
print(f"   - Damaged tool: T-047 (Post Hole Digger)")
print(f"   - Last borrower: M-023 (Sarah Chen)")
print(f"   - Checkout: {nine_days_ago}, Return: {today} (9 days - OVERDUE)")

PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/tool_library.ods
sudo chmod 666 /home/ga/Documents/tool_library.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/tool_library.ods > /tmp/calc_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_task.log
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

# Position on first sheet
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Tool Library Damage Detective Task Setup Complete ==="
echo ""
echo "📋 INVESTIGATION SCENARIO:"
echo "   Tool: Post Hole Digger (T-047)"
echo "   Status: Returned with bent handles (DAMAGED)"
echo "   Your task: Investigate who was the last borrower"
echo ""
echo "🔍 INVESTIGATION STEPS:"
echo "   1. Find last borrower in BorrowingLog sheet (Tool ID: T-047)"
echo "   2. Use VLOOKUP to get borrower name from Members sheet"
echo "   3. Calculate borrowing duration (checkout to return)"
echo "   4. Check if overdue (max 7 days allowed)"
echo "   5. Update Inventory: Mark T-047 as Damaged/Unavailable"
echo "   6. Update Members: Flag borrower for contact"
echo "   7. Document your findings"
echo ""
echo "📊 Sheets available:"
echo "   - Inventory (30 tools)"
echo "   - BorrowingLog (50+ records)"
echo "   - Members (20 members)"