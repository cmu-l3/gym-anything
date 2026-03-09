#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Thru-Hike Planner Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with trail planning data
SHEET_PATH="$WORKSPACE_DIR/trail_planning_data.xlsx"

cat > /tmp/create_trail_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()

# Remove default sheet
if 'Sheet' in wb.sheetnames:
    del wb['Sheet']

# ========================================
# Sheet 1: Trail_Segments
# ========================================
ws_trail = wb.create_sheet("Trail_Segments")

# Headers
headers_trail = ["Day", "Section_Name", "Miles", "Elev_Gain_ft", "Elev_Loss_ft", "Water_Sources", "Source_Reliable"]
ws_trail.append(headers_trail)

# Style headers
header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF")
for cell in ws_trail[1]:
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal="center")

# Trail data for 5-day hike
trail_data = [
    [1, "Trailhead to Shelter_A", 8.5, 2400, 800, "Mile 3.2, 7.8", "Yes, Seasonal"],
    [2, "Shelter_A to Peak_B", 9.2, 3100, 600, "Mile 12.8", "Yes"],
    [3, "Peak_B to Shelter_C", 7.8, 1200, 2800, "Mile 19.5", "Seasonal"],
    [4, "Shelter_C to Ridge_D", 10.1, 2600, 1400, "Mile 25.3, 28.9", "Yes, Yes"],
    [5, "Ridge_D to Trailhead", 6.4, 800, 3200, "Mile 32.0", "Yes"]
]

for row_data in trail_data:
    ws_trail.append(row_data)

# Set column widths
ws_trail.column_dimensions['A'].width = 8
ws_trail.column_dimensions['B'].width = 25
ws_trail.column_dimensions['C'].width = 10
ws_trail.column_dimensions['D'].width = 15
ws_trail.column_dimensions['E'].width = 15
ws_trail.column_dimensions['F'].width = 20
ws_trail.column_dimensions['G'].width = 18

# ========================================
# Sheet 2: Hiker_Data
# ========================================
ws_hiker = wb.create_sheet("Hiker_Data")

# Headers
ws_hiker.append(["Parameter", "Value"])
ws_hiker[1][0].fill = header_fill
ws_hiker[1][0].font = header_font
ws_hiker[1][1].fill = header_fill
ws_hiker[1][1].font = header_font

# Hiker parameters
hiker_params = [
    ["Body_Weight_lbs", 160],
    ["Base_Pack_Weight_lbs", 18],
    ["Calories_Per_Day", 3500],
    ["Calories_Per_Pound_Food", 2800],
    ["Start_Time_AM", "7:00"],
    ["Avg_Flat_Pace_mph", 3.0]
]

for param_row in hiker_params:
    ws_hiker.append(param_row)

ws_hiker.column_dimensions['A'].width = 28
ws_hiker.column_dimensions['B'].width = 12

# ========================================
# Sheet 3: Daily_Plan (EMPTY - agent must build this)
# ========================================
ws_plan = wb.create_sheet("Daily_Plan")

# Add instructions only
ws_plan['A1'] = "CREATE YOUR DAILY PLAN HERE"
ws_plan['A1'].font = Font(bold=True, size=14, color="C00000")
ws_plan['A3'] = "Required columns: Day | Hiking_Duration_hrs | Arrival_Time | Next_Water_Miles | Water_Liters | Food_Weight_lbs | Total_Pack_lbs | Weight_OK | After_Dark"
ws_plan['A3'].font = Font(italic=True, size=10)

ws_plan['A5'] = "Hints:"
ws_plan['A6'] = "- Naismith's Rule: Duration = Miles/Pace + Elevation_Gain/2000"
ws_plan['A7'] = "- Water needs: Hiking_hrs * 0.5L + Camp_hrs * 0.3L (add 1L buffer for 'Seasonal' sources)"
ws_plan['A8'] = "- Food weight per day: Calories_Per_Day / Calories_Per_Pound_Food"
ws_plan['A9'] = "- Total pack weight: Base_Weight + All_Remaining_Food + Water (in lbs, water = liters * 2.2)"
ws_plan['A10'] = "- Safe pack weight: <= Body_Weight * 0.20"
ws_plan['A11'] = "- After dark: Arrival time > 8:00 PM"

# Save workbook
wb.save(sys.argv[1])
print(f"Trail planning spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_trail_sheet.py
python3 /tmp/create_trail_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_trail_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_trail_task.log || true
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

echo "=== Thru-Hike Planner Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "==========================================="
echo "You are planning a 5-day backpacking trip in Vermont."
echo ""
echo "Your goal: Create a 'Daily_Plan' sheet with formulas that calculate:"
echo ""
echo "1. HIKING DURATION (Column B): Use Naismith's Rule"
echo "   Formula: =Trail_Segments!C2/Hiker_Data!B6 + Trail_Segments!D2/2000"
echo "   (Miles divided by pace + elevation gain divided by 2000)"
echo ""
echo "2. ARRIVAL TIME (Column C): Start time + hiking duration + 1 hour lunch"
echo "   Formula: =Hiker_Data!B5 + B2 + TIME(1,0,0)"
echo ""
echo "3. WATER NEEDS (Column E): Account for hiking + camp time"
echo "   Base formula: =B2*0.5 + 4*0.3"
echo "   Add 1L buffer for 'Seasonal' water sources (Days 1, 3)"
echo ""
echo "4. FOOD WEIGHT (Column F): Daily calories / calories per pound"
echo "   Formula: =Hiker_Data!B3/Hiker_Data!B4"
echo ""
echo "5. TOTAL PACK WEIGHT (Column G): Base + remaining food + water weight"
echo "   Day 1 formula: =Hiker_Data!B2 + F2*5 + E2*2.2"
echo "   (Adjust multiplier for remaining days: day 2 = *4, day 3 = *3, etc.)"
echo ""
echo "6. WEIGHT CHECK (Column H): Is pack weight safe?"
echo "   Formula: =IF(G2<=Hiker_Data!B1*0.2, \"OK\", \"OVER\")"
echo ""
echo "7. AFTER DARK CHECK (Column I): Will you arrive after 8 PM?"
echo "   Formula: =IF(C2>TIME(20,0,0), \"YES\", \"NO\")"
echo ""
echo "Expected Results:"
echo "  - Day 1 hiking: ~4.0 hours"
echo "  - Day 1 arrival: ~12:00 PM"
echo "  - Pack weight should decrease each day (food consumed)"
echo "  - Day 1 pack will be heaviest (all 5 days of food)"
echo ""
echo "Save your work with Ctrl+S when done!"
echo "==========================================="