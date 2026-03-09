#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Blood Sugar Log Cleanup Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy blood sugar data file
MESSY_DATA_PATH="$WORKSPACE_DIR/blood_sugar_messy.xlsx"

cat > /tmp/create_messy_data.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font
import sys
import random
from datetime import datetime, timedelta

wb = Workbook()
ws = wb.active
ws.title = "Raw Data"

# Headers
ws['A1'] = "Date"
ws['B1'] = "Time"
ws['C1'] = "Reading"
ws['D1'] = "Notes"

# Make headers bold
for cell in ['A1', 'B1', 'C1', 'D1']:
    ws[cell].font = Font(bold=True)

# Generate messy data spanning ~3 months (90 days back from today)
base_date = datetime.now() - timedelta(days=90)

# Different ways to express time categories (intentionally messy)
time_variations = {
    'fasting': ['morning', 'fasting', 'before breakfast', '7:30 AM', '8:00 AM', 'early morning'],
    'post_meal': ['after breakfast', 'after lunch', 'post-meal', 'after dinner', '1:00 PM', '7:00 PM', 'afternoon'],
    'bedtime': ['bedtime', 'before bed', 'evening', 'night', '10:00 PM', '11:00 PM']
}

# Date format variations
date_formats = ['%m/%d/%Y', '%m/%d/%y', '%b %d', '%d-%B', '%Y-%m-%d']

# Realistic blood sugar readings (with some typos)
fasting_readings = list(range(95, 170)) + [325]  # 325 is typo for 235
post_meal_readings = list(range(140, 260))
bedtime_readings = list(range(110, 190))

notes_pool = [
    "after pizza dinner", "stressed at work", "forgot to take meds", 
    "exercised today", "sick with cold", "holiday meal", 
    "ate out", "skipped breakfast", "late meal", ""
]

row = 2
dates_used = []

# Generate approximately 90 readings over 90 days (not every day, some days multiple)
for day_offset in range(90):
    current_date = base_date + timedelta(days=day_offset)
    dates_used.append(current_date)
    
    # Randomly decide how many readings this day (0-3, with bias toward 2)
    num_readings = random.choices([0, 1, 2, 3], weights=[5, 15, 60, 20])[0]
    
    for _ in range(num_readings):
        # Pick a time category
        category = random.choice(['fasting', 'post_meal', 'bedtime'])
        time_var = random.choice(time_variations[category])
        
        # Pick a reading based on category
        if category == 'fasting':
            reading = random.choice(fasting_readings)
        elif category == 'post_meal':
            reading = random.choice(post_meal_readings)
        else:
            reading = random.choice(bedtime_readings)
        
        # Format date in various ways
        date_fmt = random.choice(date_formats)
        date_str = current_date.strftime(date_fmt)
        
        # Random notes (70% chance of no note)
        note = random.choice(notes_pool) if random.random() > 0.7 else ""
        
        ws[f'A{row}'] = date_str
        ws[f'B{row}'] = time_var
        ws[f'C{row}'] = reading
        ws[f'D{row}'] = note
        
        row += 1
        
        # Add some blank rows randomly (5% chance)
        if random.random() < 0.05:
            row += 1

# Add a few obviously wrong entries (readings outside normal physiological range)
ws[f'A{row}'] = '01/15/2025'
ws[f'B{row}'] = 'morning'
ws[f'C{row}'] = 420  # Too high without context
ws[f'D{row}'] = ""
row += 1

ws[f'A{row+1}'] = '02/03/2025'
ws[f'B{row+1}'] = 'evening'
ws[f'C{row+1}'] = 45  # Very low
ws[f'D{row+1}'] = ""

# Shuffle some rows to make chronologically out of order
# (get all data rows and shuffle middle section)
all_data = []
for r in range(2, row + 2):
    row_data = [ws[f'A{r}'].value, ws[f'B{r}'].value, ws[f'C{r}'].value, ws[f'D{r}'].value]
    all_data.append(row_data)

# Shuffle middle third of data
third = len(all_data) // 3
middle_section = all_data[third:2*third]
random.shuffle(middle_section)
all_data[third:2*third] = middle_section

# Write back shuffled data
for idx, row_data in enumerate(all_data, start=2):
    ws[f'A{idx}'] = row_data[0]
    ws[f'B{idx}'] = row_data[1]
    ws[f'C{idx}'] = row_data[2]
    ws[f'D{idx}'] = row_data[3]

# Set column widths for readability
ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 20
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 25

wb.save(sys.argv[1])
print(f"Messy blood sugar data created: {sys.argv[1]}")
print(f"Total rows of data: {len(all_data)}")
PYEOF

chmod +x /tmp/create_messy_data.py
python3 /tmp/create_messy_data.py "$MESSY_DATA_PATH"
chown ga:ga "$MESSY_DATA_PATH"

echo "✅ Messy data file created at: $MESSY_DATA_PATH"

# Create the target ranges reference file
TARGET_RANGES_PATH="/home/ga/Documents/target_ranges.txt"

cat > "$TARGET_RANGES_PATH" << 'EOF'
Doctor's Target Ranges for Blood Glucose:

- Fasting (before first meal): 80-130 mg/dL
- Post-Meal (2 hours after eating): <180 mg/dL
- Bedtime: 100-140 mg/dL

Important: Readings below 70 mg/dL are concerning (hypoglycemia)
Readings consistently above targets may require medication adjustment.

Please organize your readings by these categories for tomorrow's appointment.
EOF

chown ga:ga "$TARGET_RANGES_PATH"

echo "✅ Target ranges reference created at: $TARGET_RANGES_PATH"

# Launch ONLYOFFICE with the messy spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$MESSY_DATA_PATH' > /tmp/onlyoffice_bloodsugar_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_bloodsugar_task.log || true
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

echo "=== Blood Sugar Log Cleanup Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "Maria has been tracking blood sugar for 3 months but the data is messy."
echo "Her doctor appointment is tomorrow and she needs organized data."
echo ""
echo "📝 YOUR TASK:"
echo "1. Create a new sheet called 'Organized Log' with columns:"
echo "   Date | Day of Week | Time Category | Reading (mg/dL) | Notes"
echo ""
echo "2. Clean and standardize the data:"
echo "   - Standardize Time Category to ONLY: Fasting, Post-Meal, or Bedtime"
echo "   - Sort chronologically by date"
echo "   - Remove blank rows"
echo "   - Ensure consistent date format"
echo ""
echo "3. Apply conditional formatting to Reading column:"
echo "   - Green: Target range (Fasting 80-130, Post-Meal <180, Bedtime 100-140)"
echo "   - Yellow: Elevated (Fasting 131-160, Post-Meal 180-250, Bedtime 141-180)"
echo "   - Red: Concerning (Fasting >160, Post-Meal >250, Bedtime >180)"
echo "   - Blue: Low (<70 for any)"
echo ""
echo "4. Create 'Summary Analysis' sheet with:"
echo "   - Average by Time Category (use formulas!)"
echo "   - Count of readings per category"
echo "   - Notes on patterns"
echo ""
echo "5. Save as: /home/ga/Documents/Spreadsheets/blood_sugar_organized.xlsx"
echo ""
echo "📖 Reference file available at: $TARGET_RANGES_PATH"