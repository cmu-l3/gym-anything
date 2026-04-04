#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Memorial Slideshow Organizer Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

# Create the initial spreadsheet with photo data
SHEET_PATH="$WORKSPACE_DIR/memorial_photos_raw.xlsx"

cat > /tmp/create_memorial_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font
import sys

wb = Workbook()
ws = wb.active
ws.title = "Memorial Photos"

# Headers for columns A-D (already filled)
ws['A1'] = 'Photo_Filename'
ws['B1'] = 'Source_Person'
ws['C1'] = 'Approximate_Year'
ws['D1'] = 'People_Visible'

# Make headers bold
for cell in ['A1', 'B1', 'C1', 'D1']:
    ws[cell].font = Font(bold=True)

# Sample photo data (50 rows)
photos = [
    ("IMG_2847.jpg", "Aunt Marie", "1967", "Dad as teenager"),
    ("dad_fishing_1985.jpg", "Uncle Frank", "1985", "Dad + Uncle Frank"),
    ("wedding_1989.jpg", "Sister Lisa", "1989", "Dad + Mom wedding"),
    ("blurry_uncle.jpg", "Aunt Marie", "1975", "Dad + siblings"),
    ("scan0012.tif", "Cloud Archive", "unknown", "???"),
    ("family_reunion_2001.jpg", "Sister Lisa", "2001", "Whole family"),
    ("dad_graduation.jpg", "Cloud Archive", "1970", "Dad college graduation"),
    ("birthday_party_1995.jpg", "Uncle Frank", "1995?", "Dad + kids"),
    ("IMG_8273.jpg", "Aunt Marie", "2010", "Dad + grandkids"),
    ("old_car_photo.jpg", "Cloud Archive", "1972", "Dad with first car"),
    ("duplicate_fishing_1985b.jpg", "Uncle Frank", "1985", "Dad + Uncle Frank"),
    ("mom_dad_vacation.jpg", "Sister Lisa", "1992", "Dad + Mom beach"),
    ("christmas_1978.jpg", "Aunt Marie", "1978", "Family Christmas"),
    ("dad_at_work.jpg", "Cloud Archive", "1988", "Dad at office"),
    ("IMG_5521.jpg", "Uncle Frank", "2005", "Dad retirement party"),
    ("baby_photo_1966.jpg", "Aunt Marie", "1966", "Dad as baby"),
    ("military_service.jpg", "Cloud Archive", "1971", "Dad in uniform"),
    ("scan_damaged_002.tif", "Aunt Marie", "unknown", "Dad childhood"),
    ("dad_coaching_soccer.jpg", "Sister Lisa", "1998", "Dad + youth team"),
    ("anniversary_2015.jpg", "Uncle Frank", "2015", "Dad + Mom 50th"),
    ("IMG_9012.jpg", "Aunt Marie", "2018", "Recent family dinner"),
    ("high_school_photo.jpg", "Cloud Archive", "1968", "Dad senior year"),
    ("dad_hiking.jpg", "Sister Lisa", "2012", "Dad mountain trip"),
    ("work_award_1994.jpg", "Uncle Frank", "1994", "Dad receiving award"),
    ("kids_at_beach.jpg", "Aunt Marie", "1993", "Dad + children"),
    ("IMG_3344.jpg", "Cloud Archive", "unknown", "???"),
    ("scan0034.tif", "Aunt Marie", "1969", "Dad + college friends"),
    ("boat_trip_2008.jpg", "Sister Lisa", "2008", "Dad fishing boat"),
    ("lowres_scan.jpg", "Cloud Archive", "1977", "Dad + siblings reunion"),
    ("dad_teaching_bike.jpg", "Uncle Frank", "1992", "Dad teaching kid to ride"),
    ("concert_photo_1975.jpg", "Aunt Marie", "1975?", "Dad at concert"),
    ("IMG_7821.jpg", "Sister Lisa", "2016", "Dad + grandchildren"),
    ("duplicate_wedding_89.jpg", "Aunt Marie", "1989", "Dad + Mom wedding"),
    ("professional_headshot.jpg", "Cloud Archive", "1990", "Dad work photo"),
    ("thanksgiving_2003.jpg", "Uncle Frank", "2003", "Family Thanksgiving"),
    ("dad_young_adult.jpg", "Cloud Archive", "1973", "Dad in 20s"),
    ("scan_faded_012.tif", "Aunt Marie", "unknown", "Old family photo"),
    ("sports_team_1969.jpg", "Cloud Archive", "1969", "Dad high school basketball"),
    ("IMG_4532.jpg", "Sister Lisa", "2019", "Recent birthday"),
    ("road_trip_1987.jpg", "Uncle Frank", "1987", "Dad + friends"),
    ("dad_at_hospital.jpg", "Aunt Marie", "1993", "Dad with newborn grandchild"),
    ("scan0045.tif", "Cloud Archive", "1965", "Dad as young child"),
    ("memorial_day_2011.jpg", "Sister Lisa", "2011", "Dad veteran event"),
    ("IMG_6621.jpg", "Uncle Frank", "2017", "Dad garden project"),
    ("neighborhood_bbq.jpg", "Aunt Marie", "1999", "Dad + neighbors"),
    ("dad_laughing.jpg", "Sister Lisa", "2014", "Candid happy moment"),
    ("old_house_photo.jpg", "Cloud Archive", "1976", "Dad first house"),
    ("IMG_2103.jpg", "Aunt Marie", "2013", "Dad + extended family"),
    ("scan_torn_edge.jpg", "Cloud Archive", "unknown", "Damaged old photo"),
    ("final_birthday_2020.jpg", "Sister Lisa", "2020", "Dad last birthday")
]

for idx, photo_data in enumerate(photos, start=2):
    ws[f'A{idx}'] = photo_data[0]
    ws[f'B{idx}'] = photo_data[1]
    ws[f'C{idx}'] = photo_data[2]
    ws[f'D{idx}'] = photo_data[3]

# Columns E-L are left empty for the user to fill
# Add column width adjustments for better visibility
ws.column_dimensions['A'].width = 30
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 18
ws.column_dimensions['D'].width = 25

wb.save(sys.argv[1])
print(f"Memorial photo spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_memorial_sheet.py
python3 /tmp/create_memorial_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Create requirements text file
REQUIREMENTS_PATH="$DOCS_DIR/memorial_requirements.txt"

cat > "$REQUIREMENTS_PATH" << 'EOF'
Dear Family,

First, our deepest condolences during this difficult time. Here are the details for the memorial service slideshow:

TECHNICAL REQUIREMENTS FROM VENUE:
- Final slideshow should be 3-5 minutes total duration
- Photos should be high resolution (minimum 1024x768)
- Accepted formats: JPG, PNG (no TIFF files in final slideshow)
- If a photo needs scanning/repair, please note it
- We can display 5-8 seconds per photo typically

SUGGESTED STRUCTURE:
- Childhood & Youth (1960s-1970s)
- Young Adult & Career (1970s-1980s)
- Family Years (1990s-2000s)
- Later Life & Grandchildren (2010s-2020s)

FAMILY FEEDBACK SO FAR:
- Aunt Marie strongly wants to include the fishing photo (even though it's blurry)
- Uncle Frank says we have too many duplicate wedding photos - pick the best one
- Sister Lisa requests we include at least 3 photos with grandchildren
- Please note if any photos need permission from ex-family members

REMEMBER:
- We need your organized list by tomorrow evening
- Select photos that show meaningful moments and variety
- Quality matters - blurry/damaged photos won't project well
- Keep it to 20-25 photos maximum for timing

With sympathy,
Memorial Home Staff
EOF

chown ga:ga "$REQUIREMENTS_PATH"

echo "✅ Requirements file created at: $REQUIREMENTS_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_memorial_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_memorial_task.log || true
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

echo "=== Memorial Slideshow Organizer Task Setup Complete ==="
echo ""
echo "📝 CONTEXT:"
echo "  You're organizing 50 photos for a memorial service in 3 days."
echo "  Read /home/ga/Documents/memorial_requirements.txt for full context."
echo ""
echo "📋 REQUIRED TASKS:"
echo "  1. Add column headers in E-L:"
echo "     E: Quality_Rating"
echo "     F: Life_Stage"
echo "     G: Include_in_Slideshow"
echo "     H: Slideshow_Order"
echo "     I: Display_Seconds"
echo "     J: Story_Notes"
echo "     K: Technical_Issue"
echo "     L: Family_Input"
echo ""
echo "  2. Set up data validation dropdowns:"
echo "     E: 1, 2, 3, 4, 5"
echo "     F: Childhood, Youth, Young_Adult, Family_Years, Later_Life"
echo "     G: YES, NO, MAYBE"
echo "     K: Resolution_Low, Color_Faded, Needs_Scanning, Permission_Needed, OK"
echo ""
echo "  3. Apply conditional formatting:"
echo "     - Column G = 'YES' → light green background"
echo "     - Column G = 'NO' → light gray background"
echo "     - Column E ≤ 2 → light red background"
echo "     - Column K = 'Permission_Needed' → light orange background"
echo ""
echo "  4. Fill at least 15 rows with complete data (columns E-L)"
echo "     Use filenames and years as hints for quality/life stage"
echo ""
echo "  5. Assign Slideshow_Order (column H):"
echo "     - Sequential numbers (1, 2, 3...) ONLY for photos marked YES"
echo "     - Leave blank for NO/MAYBE photos"
echo ""
echo "  6. Create summary section starting at row 55:"
echo "     A55: 'SLIDESHOW SUMMARY'"
echo "     A56: 'Total Photos Collected' | B56: =COUNTA(A2:A51)"
echo "     A57: 'Photos Marked YES' | B57: =COUNTIF(G2:G51,\"YES\")"
echo "     A58: 'Photos Marked MAYBE' | B58: =COUNTIF(G2:G51,\"MAYBE\")"
echo "     A59: 'Estimated Slideshow Duration (minutes)' | B59: =SUMIF(G2:G51,\"YES\",I2:I51)/60"
echo "     A60: 'Photos Needing Permission' | B60: =COUNTIF(K2:K51,\"Permission_Needed\")"
echo "     A61: 'Average Quality Rating (YES photos)' | B61: =AVERAGEIF(G2:G51,\"YES\",E2:E51)"
echo ""
echo "  7. Enable freeze panes on row 1"
echo "  8. Enable auto-filter on header row"
echo "  9. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIPS:"
echo "  - 'blurry', 'scan_damaged', 'lowres' → low quality (1-2)"
echo "  - 'duplicate' → likely NO"
echo "  - Photos with grandkids → YES (per Sister Lisa)"
echo "  - TIF files → mark 'Needs_Scanning' in Technical_Issue"