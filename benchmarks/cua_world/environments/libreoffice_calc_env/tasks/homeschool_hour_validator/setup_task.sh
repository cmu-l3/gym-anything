#!/bin/bash
# set -euo pipefail

echo "=== Setting up Homeschool Hour Validator Task ==="

source /workspace/scripts/task_utils.sh

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed (for creating ODS files)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq
    sudo apt-get install -y python3-odf python3-pip
fi

# Create the lesson log and requirements tables using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
import random
from datetime import datetime, timedelta

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add main sheet
table = Table(name="Lesson Log")
doc.spreadsheet.addElement(table)

# Helper function to add a cell with value
def add_cell(row, value, value_type='string'):
    cell = TableCell(valuetype=value_type)
    if value_type == 'string':
        cell.setAttribute('stringvalue', str(value))
        p = P(text=str(value))
        cell.addElement(p)
    elif value_type == 'float':
        cell.setAttribute('value', str(value))
        p = P(text=str(value))
        cell.addElement(p)
    row.addElement(cell)
    return cell

# Header row for lesson log
header_row = TableRow()
add_cell(header_row, "Date", 'string')
add_cell(header_row, "Subject", 'string')
add_cell(header_row, "Duration", 'string')
add_cell(header_row, "Description", 'string')
add_cell(header_row, "", 'string')  # Empty column E
add_cell(header_row, "Subject", 'string')  # Requirements table header (column F)
add_cell(header_row, "Minimum Hours", 'string')  # Requirements table header (column G)
table.addElement(header_row)

# Define subjects and requirements
subjects = [
    ("Mathematics", 120),
    ("Language Arts", 160),
    ("Science", 100),
    ("Social Studies", 100),
    ("Physical Education", 60),
    ("Arts", 40)
]

# Sample lesson descriptions by subject
descriptions = {
    "Mathematics": [
        "Algebra practice", "Geometry proofs", "Fractions and decimals",
        "Word problems", "Mental math", "Measurement activities",
        "Data and graphing", "Pre-algebra concepts", "Math puzzles"
    ],
    "Language Arts": [
        "Reading comprehension", "Creative writing", "Grammar practice",
        "Spelling exercises", "Literature discussion", "Journal writing",
        "Poetry analysis", "Book report", "Vocabulary building"
    ],
    "Science": [
        "Biology experiment", "Chemistry lab", "Physics demonstration",
        "Nature observation", "Scientific method", "Earth science",
        "Plant life cycle", "Simple machines", "Weather tracking"
    ],
    "Social Studies": [
        "History reading", "Geography mapping", "Civics discussion",
        "Timeline activity", "Historical fiction", "Current events",
        "Cultural studies", "Map skills", "Government structure"
    ],
    "Physical Education": [
        "Outdoor play", "Bike riding", "Swimming", "Yoga practice",
        "Team sports", "Nature hike", "Dance class", "Gymnastics"
    ],
    "Arts": [
        "Drawing practice", "Painting", "Music lesson", "Craft project",
        "Theater rehearsal", "Art history", "Pottery", "Photography"
    ]
}

# Generate ~80 lesson entries
# Target totals (with some under requirements for testing):
target_hours = {
    "Mathematics": 125.5,      # COMPLIANT (+5.5)
    "Language Arts": 168.0,    # COMPLIANT (+8.0)
    "Science": 95.5,           # DEFICIENT (-4.5)
    "Social Studies": 103.0,   # COMPLIANT (+3.0)
    "Physical Education": 57.0,# DEFICIENT (-3.0)
    "Arts": 38.5               # DEFICIENT (-1.5)
}

# Generate entries to approximate target hours
start_date = datetime(2024, 9, 3)  # School year start
lesson_entries = []

for subject, target in target_hours.items():
    remaining = target
    num_entries = random.randint(12, 18)  # Vary entry count per subject
    
    for i in range(num_entries):
        if i < num_entries - 1:
            # Random duration for most entries
            duration = random.choice([0.5, 1.0, 1.5, 2.0, 2.5])
            duration = min(duration, remaining)  # Don't exceed target
        else:
            # Last entry: use remaining hours
            duration = round(remaining, 1)
        
        remaining -= duration
        
        # Random date within school year
        days_offset = random.randint(0, 240)
        entry_date = start_date + timedelta(days=days_offset)
        
        # Random description
        desc = random.choice(descriptions[subject])
        
        lesson_entries.append({
            'date': entry_date.strftime('%Y-%m-%d'),
            'subject': subject,
            'duration': duration,
            'description': desc
        })

# Sort by date
lesson_entries.sort(key=lambda x: x['date'])

# Add lesson entries and requirements table side by side
for idx, entry in enumerate(lesson_entries):
    row = TableRow()
    
    # Lesson log columns (A-D)
    add_cell(row, entry['date'], 'string')
    add_cell(row, entry['subject'], 'string')
    add_cell(row, str(entry['duration']), 'float')
    add_cell(row, entry['description'], 'string')
    
    # Empty column (E)
    add_cell(row, "", 'string')
    
    # Requirements table (F-G) - only for first 6 rows
    if idx < len(subjects):
        subject_name, min_hours = subjects[idx]
        add_cell(row, subject_name, 'string')
        add_cell(row, str(min_hours), 'float')
    else:
        add_cell(row, "", 'string')
        add_cell(row, "", 'string')
    
    table.addElement(row)

# Add some empty rows to make space for summary
for _ in range(20):
    row = TableRow()
    for _ in range(10):
        add_cell(row, "", 'string')
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/homeschool_log.ods")
print("✅ Created homeschool lesson log with requirements table")
print(f"   Total entries: {len(lesson_entries)}")
print(f"   Date range: {lesson_entries[0]['date']} to {lesson_entries[-1]['date']}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/homeschool_log.ods
sudo chmod 666 /home/ga/Documents/homeschool_log.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/homeschool_log.ods > /tmp/calc_homeschool.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_homeschool.log || true
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Homeschool Hour Validator Task Setup Complete ==="
echo ""
echo "📚 SCENARIO:"
echo "   Sarah is a homeschooling parent facing a portfolio review in 2 weeks."
echo "   She needs to verify compliance with state minimum instruction hours."
echo ""
echo "📋 YOUR TASK:"
echo "   1. Review the Lesson Log (columns A-D) and State Requirements (columns F-G)"
echo "   2. Create a Summary Analysis section (suggest starting around row 85)"
echo "   3. Use SUMIF formulas to calculate total hours per subject"
echo "   4. Compare against requirements and calculate deficiency/surplus"
echo "   5. Use IF formulas to show COMPLIANT or DEFICIENT status"
echo "   6. Apply conditional formatting (red for deficient, green for compliant)"
echo ""
echo "💡 KEY FORMULAS:"
echo "   SUMIF: =SUMIF(\$B\$2:\$B\$82, \"Mathematics\", \$C\$2:\$C\$82)"
echo "   IF: =IF(difference>=0, \"COMPLIANT\", \"DEFICIENT\")"
echo ""
echo "✅ State Requirements:"
echo "   Mathematics: 120 hrs | Language Arts: 160 hrs | Science: 100 hrs"
echo "   Social Studies: 100 hrs | Physical Education: 60 hrs | Arts: 40 hrs"