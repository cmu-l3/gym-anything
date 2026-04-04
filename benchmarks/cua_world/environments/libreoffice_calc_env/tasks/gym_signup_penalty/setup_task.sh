#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Gym Class Sign-up Penalty Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install Python ODF library if not present
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy library..."
# sudo apt-get update -qq
    sudo apt-get install -y python3-odf
fi

# Create the gym bookings ODS file with sample data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
import datetime
import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# ===== SHEET 1: Bookings =====
bookings_table = Table(name="Bookings")
doc.spreadsheet.addElement(bookings_table)

# Headers
headers = ["member_id", "class_date", "class_time", "booking_timestamp", 
           "cancellation_timestamp", "attended", "excuse_code"]
header_row = TableRow()
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
bookings_table.addElement(header_row)

# Generate 200 booking records with realistic patterns
base_date = datetime.date(2024, 1, 1)
member_ids = list(range(1001, 1051))  # 50 members
class_times = ["06:00", "08:00", "12:00", "17:00", "18:00", "19:00"]

bookings_data = []
for i in range(200):
    days_offset = random.randint(0, 89)  # 90 days of data
    class_date = base_date + datetime.timedelta(days=days_offset)
    class_time = random.choice(class_times)
    member_id = random.choice(member_ids)
    
    # 70% attended, 20% no-show, 10% timely cancel
    outcome = random.choices(["attended", "no_show", "timely_cancel", "late_cancel"],
                            weights=[70, 15, 10, 5])[0]
    
    booking_ts = class_date - datetime.timedelta(days=random.randint(1, 7))
    
    if outcome == "attended":
        attended = "TRUE"
        cancel_ts = ""
        excuse = ""
    elif outcome == "no_show":
        attended = "FALSE"
        cancel_ts = ""  # No cancellation
        # 5% have excuse codes
        excuse = random.choice(["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "MEDICAL"]) if random.random() < 0.05 else ""
    elif outcome == "timely_cancel":
        attended = "FALSE"
        hours_before = random.uniform(2.5, 24)
        cancel_datetime = datetime.datetime.combine(class_date, datetime.time(int(class_time.split(':')[0]), 0)) - datetime.timedelta(hours=hours_before)
        cancel_ts = cancel_datetime.strftime("%Y-%m-%d %H:%M")
        excuse = ""
    else:  # late_cancel
        attended = "FALSE"
        hours_before = random.uniform(0.1, 1.9)
        cancel_datetime = datetime.datetime.combine(class_date, datetime.time(int(class_time.split(':')[0]), 0)) - datetime.timedelta(hours=hours_before)
        cancel_ts = cancel_datetime.strftime("%Y-%m-%d %H:%M")
        excuse = ""
    
    bookings_data.append({
        "member_id": member_id,
        "class_date": class_date.strftime("%Y-%m-%d"),
        "class_time": class_time,
        "booking_timestamp": booking_ts.strftime("%Y-%m-%d"),
        "cancellation_timestamp": cancel_ts,
        "attended": attended,
        "excuse_code": excuse
    })

# Add 8 duplicate entries (data quality issue)
for i in range(8):
    bookings_data.append(bookings_data[random.randint(0, len(bookings_data)-1)].copy())

# Shuffle to mix duplicates
random.shuffle(bookings_data)

# Add booking rows
for booking in bookings_data:
    row = TableRow()
    for key in headers:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(booking[key])))
        row.addElement(cell)
    bookings_table.addElement(row)

# ===== SHEET 2: Members =====
members_table = Table(name="Members")
doc.spreadsheet.addElement(members_table)

# Headers
member_headers = ["member_id", "name", "age_group", "membership_type", "join_date"]
header_row = TableRow()
for header in member_headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
members_table.addElement(header_row)

# Generate 50 members with name variations (data quality issue)
first_names = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry", 
               "Iris", "Jack", "Karen", "Leo", "Mary", "Nick", "Olivia", "Paul",
               "Quinn", "Rachel", "Steve", "Tina", "Uma", "Victor", "Wendy", "Xavier",
               "Yara", "Zack", "Anna", "Ben", "Clara", "Dan", "Emma", "Felix",
               "Gina", "Hugo", "Ivy", "Jake", "Kate", "Liam", "Mia", "Noah",
               "Owen", "Pam", "Quincy", "Rita", "Sam", "Tom", "Ursula", "Vera", "Will", "Zoe"]
last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", 
              "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez",
              "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin"]

for i, member_id in enumerate(member_ids):
    name = f"{first_names[i]} {last_names[i % len(last_names)]}"
    
    # Introduce name inconsistencies for some members
    if i % 5 == 0:
        name = name.lower()  # "alice smith"
    elif i % 7 == 0:
        name = name.upper()  # "ALICE SMITH"
    elif i % 11 == 0:
        name = f"  {name}  "  # Extra spaces
    
    age_group = random.choice(["18-25", "26-35", "36-45", "46-55", "56+"])
    membership_type = random.choice(["Basic", "Premium", "Student", "Senior"])
    join_date = (datetime.date(2018, 1, 1) + datetime.timedelta(days=random.randint(0, 1800))).strftime("%Y-%m-%d")
    
    row = TableRow()
    for value in [member_id, name, age_group, membership_type, join_date]:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    members_table.addElement(row)

# ===== SHEET 3: Rules =====
rules_table = Table(name="Rules")
doc.spreadsheet.addElement(rules_table)

# Headers
rules_header_row = TableRow()
for header in ["parameter", "value"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    rules_header_row.addElement(cell)
rules_table.addElement(rules_header_row)

# Rule parameters
rules = [
    ("grace_period_hours", "2"),
    ("strikes_for_warning", "2"),
    ("strikes_for_restriction", "3"),
    ("rolling_window_days", "30")
]

for param, value in rules:
    row = TableRow()
    cell1 = TableCell(valuetype="string")
    cell1.addElement(P(text=param))
    row.addElement(cell1)
    cell2 = TableCell(valuetype="string")
    cell2.addElement(P(text=value))
    row.addElement(cell2)
    rules_table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/gym_bookings.ods")
print("✅ Created gym_bookings.ods with 200 bookings, 50 members, and penalty rules")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/gym_bookings.ods
sudo chmod 666 /home/ga/Documents/gym_bookings.ods

# Verify file was created
if [ -f "/home/ga/Documents/gym_bookings.ods" ]; then
    echo "✅ Gym bookings file created successfully"
    ls -lh /home/ga/Documents/gym_bookings.ods
else
    echo "❌ ERROR: Failed to create gym_bookings.ods"
    exit 1
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/gym_bookings.ods > /tmp/calc_gym_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_gym_task.log || true
    # Don't exit - allow task to continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - allow task to continue
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
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

# Navigate to Bookings sheet (should be first sheet by default)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Gym Penalty Calculator Task Setup Complete ==="
echo ""
echo "📊 Dataset Summary:"
echo "  - 200 booking records (includes 8 duplicates to remove)"
echo "  - 50 members (with name formatting inconsistencies)"
echo "  - Penalty rules: 2-hour grace period, 2 strikes = warning, 3 strikes = restricted"
echo ""
echo "📝 Instructions:"
echo "  1. Clean data: Remove duplicates, standardize names"
echo "  2. Calculate hours_before_class for each booking"
echo "  3. Determine strike_earned (0 or 1) based on rules"
echo "  4. Create Member_Penalties sheet with rolling 30-day strike counts"
echo "  5. Assign penalty_status: GOOD_STANDING, WARNING, or RESTRICTED"
echo "  6. Apply conditional formatting (green/yellow/red)"
echo "  7. Create Fairness_Summary sheet analyzing bias by demographics"
echo "  8. Save the file when complete"