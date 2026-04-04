#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Thru-Hike Resupply Planner Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create trail data reference file on desktop
TRAIL_DATA_PATH="/home/ga/Desktop/AT_trail_data.txt"

cat > "$TRAIL_DATA_PATH" << 'TRAILEOF'
====================================================================
APPALACHIAN TRAIL: HARPERS FERRY TO DAMASCUS SECTION
====================================================================
Total Distance: ~140 miles
Estimated Duration: 12-16 days
Difficulty: Moderate with some challenging climbs

TRAIL LANDMARKS & LOGISTICS:
====================================================================

Mile 0.0    : Harpers Ferry, WV (START)
              • Trail Town with full resupply (grocery, outfitter)
              • Hostels and lodging available
              • US-340 Road Access (bailout point)

Mile 8.2    : Ed Garvey Shelter
              • Water source, privy, tent sites

Mile 15.3   : Crampton Gap - Gathland State Park
              • MD-572 Road Crossing (BAILOUT POINT)
              • Parking area, historical site

Mile 23.1   : Annapolis Rocks
              • Popular camping area, views
              • Water 0.3 miles off trail

Mile 30.4   : Pine Grove Furnace State Park
              • PA-233 Road Crossing
              • Small camp store (limited supplies)

Mile 42.6   : Boiling Springs, PA (RESUPPLY TOWN)
              • Full grocery store, pizza, ice cream
              • PA-174 Road Access
              • Post office for mail drops
              • 0.5 miles off trail

Mile 55.8   : Darlington Shelter
              • Water, tent platforms

Mile 68.3   : US-11 / I-81 Crossing (BAILOUT POINT)
              • Major highway access
              • Motels 2 miles west in Duncannon

Mile 73.5   : Duncannon, PA (RESUPPLY TOWN)
              • Full services: grocery, restaurants, lodging
              • US-11/15 Highway Access
              • Outfitter, post office

Mile 82.1   : Peters Mountain Shelter
              • Water, privy, reliable spring

Mile 95.4   : Clarks Ferry Bridge
              • PA-225 Road Crossing

Mile 108.7  : PA-501 Highway Crossing (BAILOUT POINT)
              • Parking area
              • Pine Grove town 3 miles east

Mile 118.2  : Eagles Nest Shelter
              • Water, tent sites

Mile 125.9  : Port Clinton, PA (RESUPPLY OPTION)
              • Small town with limited supplies
              • PA-61 Road Access
              • Pavilion for overnight camping

Mile 136.4  : Windsor Furnace Shelter
              • Last shelter before finish

Mile 140.0  : Damascus, VA (FINISH / Trail Days town)
              • Full resupply available
              • US-58 Road Access

====================================================================
PLANNING NOTES:
====================================================================

FOOD PLANNING:
• Carry 2 lbs of food per day (4,000-5,000 calories)
• Maximum comfortable carry: 6-7 days of food (12-14 lbs)
• Plan resupply every 5-7 days to balance weight vs. convenience

DAILY MILEAGE TARGETS:
• Conservative: 8-10 miles/day (allows for rest days)
• Moderate: 10-12 miles/day (steady progress)
• Aggressive: 12-15 miles/day (experienced hikers only)

RESUPPLY STRATEGY OPTIONS:
• Option A: Resupply at Boiling Springs (Day 5) and Duncannon (Day 9)
• Option B: Resupply at Duncannon (Day 7) and Port Clinton (Day 13)
• Option C: Single resupply at Duncannon (Day 7) - requires carrying more weight

BAILOUT POINTS:
Major road crossings for emergency exits:
• Crampton Gap (Mile 15.3) - MD-572
• US-11 near Duncannon (Mile 68.3) - I-81 access
• PA-501 (Mile 108.7) - to Pine Grove
• Additional: PA-174 at Boiling Springs, US-58 at Damascus

WATER SOURCES:
Most shelters have reliable water. Carry 2-3 liters between sources.
Dry stretches in summer require extra planning.

WEATHER CONSIDERATIONS:
Spring/Fall: 40-70°F, rain likely
Summer: 70-85°F, afternoon thunderstorms
Winter: Not recommended without experience

====================================================================
TRAILEOF

chown ga:ga "$TRAIL_DATA_PATH"

echo "✅ Trail data reference created at: $TRAIL_DATA_PATH"

# Create a blank spreadsheet with minimal setup
SHEET_PATH="$WORKSPACE_DIR/AT_Section_Hike_Plan.xlsx"

cat > /tmp/create_hike_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Hike Plan"

# Add title row
ws['A1'] = "APPALACHIAN TRAIL SECTION HIKE PLANNER"
ws['A1'].font = Font(bold=True, size=14)
ws.merge_cells('A1:H1')

# Add instruction row
ws['A2'] = "Instructions: Create a 14-day hike plan with daily mileage, cumulative distance (use formulas!), food weight, resupply towns, and bailout points"
ws['A2'].font = Font(italic=True, size=9)
ws.merge_cells('A2:H2')

# The user needs to create the column headers and all data
ws['A4'] = "[Create your column headers here: Day, Start Point, End Point, Miles (Daily), Miles (Cumulative), Food Weight, Resupply Location, Bailout Point]"
ws['A4'].font = Font(italic=True)

wb.save(sys.argv[1])
print(f"Blank hike planning spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_hike_sheet.py
python3 /tmp/create_hike_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_hike_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_hike_task.log || true
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

# Open the trail data file for reference (in gedit or similar)
echo "Opening trail data reference file..."
su - ga -c "DISPLAY=:1 gedit '$TRAIL_DATA_PATH' > /tmp/gedit_trail.log 2>&1 &" || true
sleep 2

# Re-focus ONLYOFFICE so it's the primary window
focus_onlyoffice_window

echo "=== Thru-Hike Resupply Planner Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "You're planning a 2-week, 140-mile section hike on the Appalachian Trail."
echo "You need to create a resupply plan that balances food weight against town stops."
echo ""
echo "📝 REQUIRED TASKS:"
echo "  1. Create column headers in your spreadsheet (starting at row 3 or 4):"
echo "     - Day (1-14)"
echo "     - Start Point (shelter/landmark name)"
echo "     - End Point (shelter/landmark name)"
echo "     - Miles (Daily) - how many miles that day"
echo "     - Miles (Cumulative) - total miles so far (USE FORMULAS!)"
echo "     - Food Weight (lbs) - starts ~2 lbs/day, decreases as you eat"
echo "     - Resupply Location - mark 2-3 towns where you'll resupply"
echo "     - Bailout Point - mark at least 3 road crossings for emergencies"
echo ""
echo "  2. Fill in 14 days of hiking data using the trail reference file"
echo "  3. Use realistic daily mileage: 8-12 miles/day for sustainable pace"
echo "  4. Create SUM formula for cumulative mileage (e.g., =SUM(\$D\$5:D5))"
echo "  5. Plan resupply stops every 5-7 days (e.g., Boiling Springs Day 5, Duncannon Day 9)"
echo "  6. Mark at least 3 bailout points at road crossings"
echo "  7. Calculate food weight (starts at ~28 lbs for 14 days, decreases after eating/resupply)"
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "📄 Reference file open in gedit: AT_trail_data.txt"
echo "💡 TIP: Use the trail data to find realistic shelter names and resupply towns!"