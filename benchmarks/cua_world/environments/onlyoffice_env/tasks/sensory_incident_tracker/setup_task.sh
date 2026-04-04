#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sensory Incident Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw incident data spreadsheet
RAW_DATA_PATH="$WORKSPACE_DIR/sensory_raw_notes.xlsx"

cat > /tmp/create_sensory_raw.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Raw_Notes"

# Add headers
headers = ["Date", "Time", "Location", "What_Happened", "Trigger_Notes", "How_Bad", "What_Helped"]
for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)

# Add messy incident data (realistic, inconsistent format)
incidents = [
    ["3/12", "morning", "school dropoff", "refused to get out of car, covering ears", 
     "fire drill happening nearby", "meltdown", "had to leave, late to work"],
    
    ["3/12", "~2pm", "grocery store", "screaming, hitting self", 
     "fluorescent lights + loud music + too many people", "really bad 8/10", "noise cancelling headphones in car after"],
    
    ["3/14", "evening", "home", "crying, hiding under blanket", 
     "tag in new shirt", "manageable 4/10", "cut out tag, calmed in 10 min"],
    
    ["3/15", "7:45am", "breakfast", "refused to eat, threw bowl", 
     "food texture wrong (yogurt had lumps)", "6/10", "offered alternative, took 30 min to calm"],
    
    ["3/17", "afternoon 3pm", "birthday party", "shut down, went non-verbal", 
     "balloon pop + kids screaming + sticky hands from cake", "severe 9/10", "left party early, weighted blanket at home"],
    
    ["3/19", "morning school", "called from nurse office", "took off shoes and socks, crawling under desk", 
     "seams in socks + tight shoes", "7/10", "brought seamless socks to school"],
    
    ["3/21", "11am", "restaurant", "refused to sit, pacing", 
     "cooking smells too strong + chair feels weird", "5/10", "moved to outdoor seating"],
    
    ["3/23", "bedtime 8pm", "bathroom", "screaming during bath", 
     "water temperature, soap smell", "8/10", "skipped bath, will try tomorrow"],
    
    ["3/24", "morning", "getting dressed", "aggressive, kicking", 
     "certain fabric feels scratchy", "6/10", "changed to soft shirt"],
    
    ["3/26", "afternoon", "park", "ran away, wouldn't come back", 
     "other kids too close, touching playground equipment others touched", "7/10", "sensory break on bench, brought hand wipes"],
    
    ["3/28", "12pm", "cafeteria", "refused to eat lunch", 
     "smell of someone else's food, noise level", "6/10", "ate in quiet room"],
    
    ["3/29", "evening", "family dinner", "tantrum, threw food", 
     "foods touching on plate + family talking loud", "8/10", "divided plate, quiet dinner"],
    
    ["3/30", "morning 7am", "bedroom", "couldn't get dressed, meltdown", 
     "lights too bright, pajamas twisted in sleep", "7/10", "dimmed lights, deep pressure"],
    
    ["4/1", "afternoon 2:30pm", "library", "crying, wanted to leave", 
     "fluorescent lights + air conditioning hum", "5/10", "sunglasses helped a little"],
    
    ["4/2", "morning", "car", "screaming, unbuckled seatbelt", 
     "tag sticking out + seatbelt too tight", "6/10", "removed tag, loosened belt"],
]

for row_idx, incident in enumerate(incidents, start=2):
    for col_idx, value in enumerate(incident, start=1):
        ws.cell(row=row_idx, column=col_idx, value=value)

# Adjust column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 20
ws.column_dimensions['D'].width = 45
ws.column_dimensions['E'].width = 50
ws.column_dimensions['F'].width = 18
ws.column_dimensions['G'].width = 45

wb.save(sys.argv[1])
print(f"Raw sensory incident data created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_sensory_raw.py
python3 /tmp/create_sensory_raw.py "$RAW_DATA_PATH"
chown ga:ga "$RAW_DATA_PATH"

echo "✅ Raw data spreadsheet created at: $RAW_DATA_PATH"

# Launch ONLYOFFICE with the raw data spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$RAW_DATA_PATH' > /tmp/onlyoffice_sensory_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_sensory_task.log || true
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

echo "=== Sensory Incident Tracker Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "You are a parent whose child has sensory processing challenges. You've been"
echo "tracking incidents in rough notes. Your occupational therapist needs organized"
echo "data to identify patterns and develop a sensory diet plan."
echo ""
echo "📝 YOUR TASK:"
echo "Transform the raw incident notes into a structured analysis spreadsheet."
echo ""
echo "🎯 REQUIRED OUTPUTS (save as: sensory_analysis_for_OT.xlsx):"
echo ""
echo "1. CLEANED INCIDENT LOG with standardized columns:"
echo "   - Date (standardized format)"
echo "   - Time Period (Morning/Midday/Afternoon/Evening)"
echo "   - Severity (numeric 1-10 scale)"
echo "   - Trigger Category (Auditory/Tactile/Visual/Olfactory/Multi-sensory)"
echo "   - Location Type (Home/School/Public)"
echo "   - Intervention Success (Yes/No/Partial)"
echo ""
echo "2. TRIGGER FREQUENCY ANALYSIS:"
echo "   - Count incidents by trigger type (use formulas like COUNTIF)"
echo "   - Calculate average severity by trigger type"
echo ""
echo "3. TIME-OF-DAY PATTERN ANALYSIS:"
echo "   - Group incidents by time period"
echo "   - Count or average severity per period"
echo ""
echo "4. SEVERITY HIGHLIGHTING:"
echo "   - Mark or highlight incidents with severity ≥7"
echo "   - Use conditional formatting or a flag column"
echo ""
echo "💡 TRIGGER CATEGORIZATION GUIDE:"
echo "   - Fire drill, balloon pop, screaming, loud music → Auditory"
echo "   - Tags, seams, fabric, food texture, water temp → Tactile"
echo "   - Fluorescent lights, bright lights → Visual"
echo "   - Cooking smells, soap smell, food smells → Olfactory"
echo "   - Multiple triggers together → Multi-sensory"
echo ""
echo "⚠️  REMEMBER:"
echo "   - Transfer at least 12 of 15 incidents"
echo "   - Use formulas for calculations (not manual typing)"
echo "   - Save as: /home/ga/Documents/Spreadsheets/sensory_analysis_for_OT.xlsx"
echo ""