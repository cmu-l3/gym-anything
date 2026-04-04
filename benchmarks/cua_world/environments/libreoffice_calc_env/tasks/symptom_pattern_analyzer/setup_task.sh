#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Symptom Pattern Analyzer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install Python ODF library if not present
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy library..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create symptom log ODS file with messy realistic data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
import datetime
import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Symptom Log"
table = Table(name="Symptom Log")
doc.spreadsheet.addElement(table)

# Define header row
headers = ["Date", "Time", "Severity", "Symptoms_Text", "Possible_Trigger"]
header_row = TableRow()
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
table.addElement(header_row)

# Generate realistic symptom log data (28 days, 12-15 entries)
# Start date: 4 weeks ago
start_date = datetime.date.today() - datetime.timedelta(days=28)

# Symptoms and triggers for realism
symptoms_list = [
    "Throbbing headache, mild nausea",
    "Sharp pain behind eyes",
    "Dull ache, sensitivity to light",
    "Tension headache, neck stiffness",
    "Migraine - severe pain, aura",
    "Headache with fatigue",
    "Pulsing pain on right side",
    "Moderate headache, irritability",
]

triggers_list = [
    "Skipped breakfast",
    "Long screen time (6+ hrs)",
    "Poor sleep (4 hrs)",
    "Stress at work",
    "Unknown",
    "Skipped lunch",
    "Dehydration",
    "Late night (1 AM bedtime)",
    "Argument/stress",
    "Bright lights",
]

# Generate 13 entries with irregular intervals
entry_dates = []
current_date = start_date

# Intentionally cluster more entries on weekends
for i in range(13):
    # Random interval: 1-5 days, with shorter intervals on weekends
    if current_date.weekday() >= 5:  # Saturday or Sunday
        interval = random.choice([1, 1, 2, 2, 3])  # More likely shorter
    else:
        interval = random.choice([1, 2, 3, 4, 5])
    
    current_date += datetime.timedelta(days=interval)
    if current_date > datetime.date.today():
        break
    entry_dates.append(current_date)

# Shuffle to add some messiness (but keep mostly chronological)
random.shuffle(entry_dates)
entry_dates.sort()

# Add some weekend bias
weekend_boost = [d for d in entry_dates if d.weekday() >= 5]
if len(weekend_boost) < 5:
    # Add a couple more weekend entries
    for _ in range(2):
        weekend_date = random.choice([d for d in entry_dates if d.weekday() >= 5] or entry_dates)
        new_date = weekend_date + datetime.timedelta(days=random.choice([1, 7, 14]))
        if new_date <= datetime.date.today():
            entry_dates.append(new_date)

entry_dates = sorted(entry_dates)[:13]  # Limit to 13 entries

# Create data rows
for idx, entry_date in enumerate(entry_dates):
    row = TableRow()
    
    # Date (mix formats for messiness - but keep parseable)
    date_cell = TableCell(valuetype="date", datevalue=entry_date.strftime("%Y-%m-%d"))
    date_cell.addElement(P(text=entry_date.strftime("%Y-%m-%d")))
    row.addElement(date_cell)
    
    # Time
    hour = random.choice([7, 8, 9, 10, 11, 14, 15, 16, 17, 18, 19, 20])
    minute = random.choice([0, 15, 30, 45])
    time_str = f"{hour:02d}:{minute:02d}"
    time_cell = TableCell(valuetype="string")
    time_cell.addElement(P(text=time_str))
    row.addElement(time_cell)
    
    # Severity (1-10, with 2-3 blank entries)
    if idx in [3, 8]:  # Leave some blank
        severity_cell = TableCell()
        row.addElement(severity_cell)
    else:
        severity = random.randint(4, 9)  # Realistic range
        severity_cell = TableCell(valuetype="float", value=str(severity))
        severity_cell.addElement(P(text=str(severity)))
        row.addElement(severity_cell)
    
    # Symptoms text
    symptom_text = random.choice(symptoms_list)
    symptom_cell = TableCell(valuetype="string")
    symptom_cell.addElement(P(text=symptom_text))
    row.addElement(symptom_cell)
    
    # Possible trigger
    trigger_text = random.choice(triggers_list)
    trigger_cell = TableCell(valuetype="string")
    trigger_cell.addElement(P(text=trigger_text))
    row.addElement(trigger_cell)
    
    table.addElement(row)

# Add empty rows for workspace
for _ in range(20):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/symptom_log.ods"
doc.save(output_path)
print(f"Created symptom log: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/symptom_log.ods
sudo chmod 666 /home/ga/Documents/symptom_log.ods

echo "✅ Created symptom_log.ods with realistic messy data"

# Launch LibreOffice Calc with the symptom log
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/symptom_log.ods > /tmp/calc_symptom_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_symptom_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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

# Position cursor at A1 for good starting point
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Symptom Pattern Analyzer Task Setup Complete ==="
echo "📋 Task: Analyze symptom log data"
echo "📝 Instructions:"
echo "  1. Add 'Day_of_Week' column (F) with day names using TEXT() formula"
echo "  2. Add 'Days_Since_Last' column (G) with interval calculations"
echo "  3. Add 'Is_Weekend' column (H) with Yes/No classification"
echo "  4. Create summary statistics section with formulas:"
echo "     - Total Episodes (COUNT)"
echo "     - Average Severity (AVERAGE)"
echo "     - Days Covered (MAX - MIN dates)"
echo "     - Average Days Between Episodes"
echo "     - Weekend vs Weekday episode counts"
echo "💡 Tip: Use formulas, not hardcoded values!"