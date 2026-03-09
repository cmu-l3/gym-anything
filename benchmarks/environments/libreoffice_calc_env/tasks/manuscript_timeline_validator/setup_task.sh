#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Manuscript Timeline Validator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the scene breakdown CSV with planted conflicts
cat > /home/ga/Documents/mystery_novel_scenes.csv << 'CSVEOF'
Scene #,Chapter,Timestamp,POV Character,Location,Characters Present,Scene Type
1,1,2024-03-15 09:00,Sarah,Precinct,Sarah Morrison; Detective Wong; Captain Harris,Normal
2,1,2024-03-15 10:30,Marcus,Coffee Shop,Marcus Cole; Jennifer Blake,Normal
3,1,2024-03-15 11:00,Sarah,Crime Scene,Sarah Morrison; Detective Wong; Forensics Team,Normal
4,1,2024-03-15 14:00,Sarah,Precinct,Sarah Morrison; Captain Harris,Normal
5,2,2024-03-15 15:30,Marcus,Library,Marcus Cole; Librarian; Jennifer Blake,Normal
6,2,2024-03-15 16:00,Jennifer,Cafe,Jennifer Blake; Marcus Cole,Normal
7,2,2024-03-15 17:00,Sarah,Witness Home,Sarah Morrison; Mrs. Johnson,Normal
8,2,2024-03-14 10:00,Sarah,Precinct,Sarah Morrison; Detective Wong,Flashback
9,3,2024-03-15 18:30,Marcus,Restaurant,Marcus Cole; Jennifer Blake; Chef,Normal
10,3,2024-03-15 19:00,Sarah,Apartment,Sarah Morrison; Tom Morrison,Normal
11,3,2024-03-15 20:00,Detective Wong,Lab,Detective Wong; Lab Tech,Normal
12,3,2024-03-15 21:00,Sarah,Airport Terminal,Sarah Morrison; Airport Security,Normal
12,3,2024-03-15 21:00,Sarah,Precinct,Sarah Morrison; Captain Harris,Normal
13,4,2024-03-16 08:00,Marcus,Office,Marcus Cole; Colleague,Normal
14,4,2024-03-16 09:30,Sarah,District Attorney Office,Sarah Morrison; DA Peterson; Detective Wong,Normal
15,4,2024-03-16 11:00,Jennifer,Phone Call,Jennifer Blake,Normal
16,4,2024-03-16 12:00,Sarah,Restaurant,Sarah Morrison; Detective Wong,Normal
17,5,2024-03-16 14:00,Marcus,Warehouse,Marcus Cole; Suspect,Normal
18,5,2024-03-16 15:30,Sarah,Precinct,Sarah Morrison; Captain Harris; Detective Wong,Normal
19,5,2024-03-16 16:00,Detective Wong,Evidence Room,Detective Wong; Officer Chen,Normal
20,5,2024-03-16 17:00,Sarah,Gym,Sarah Morrison; Personal Trainer,Normal
21,6,2024-03-16 19:00,Marcus,Home,Marcus Cole; Roommate,Normal
22,6,2024-03-16 20:00,Sarah,Bar,Sarah Morrison; Detective Wong; Informant,Normal
23,6,2024-03-16 21:30,Marcus,Surveillance Van,Detective Wong; Officer Chen; Sarah Morrison,Normal
24,7,2024-03-17 07:00,Sarah,Precinct,Sarah Morrison; Captain Harris,Normal
25,7,2024-03-17 09:00,Marcus,Court House,Marcus Cole; Jennifer Blake; Lawyer,Normal
26,7,2024-03-17 11:00,Jennifer,Coffee Shop,Jennifer Blake; Source,Normal
27,7,2024-03-17 13:00,Sarah,Suspect Home,Sarah Morrison; Detective Wong; Suspect Wife,Normal
28,8,2024-03-17 15:00,Marcus,Park,Marcus Cole; Jennifer Blake,Normal
29,8,2024-03-17 16:30,Sarah,Precinct,Sarah Morrison; Captain Harris; FBI Agent,Normal
30,8,2024-03-17 18:00,Detective Wong,Stakeout Location,Detective Wong; Officer Chen,Normal
31,8,2024-03-17 17:30,Sarah,Crime Scene,Sarah Morrison; Forensics Team,Normal
32,9,2024-03-17 20:00,Marcus,Safe House,Marcus Cole; Jennifer Blake; Marshal,Normal
33,9,2024-03-17 21:30,Sarah,Hospital,Sarah Morrison; Witness; Doctor,Normal
34,9,2024-03-17 23:00,Detective Wong,Precinct,Detective Wong; Night Shift Officer,Normal
35,10,2024-03-18 06:00,Sarah,Home,Sarah Morrison; Tom Morrison,Normal
36,10,2024-03-18 08:00,Marcus,Precinct,Marcus Cole; Sarah Morrison; Captain Harris,Normal
37,10,2024-03-18 10:00,Sarah,Interrogation Room,Sarah Morrison; Detective Wong; Suspect,Normal
38,10,2024-03-18 12:00,Jennifer,Editor Office,Jennifer Blake; Editor,Normal
39,11,2024-03-18 14:00,Sarah,DA Office,Sarah Morrison; DA Peterson,Normal
40,11,2024-03-18 15:30,Marcus,Warehouse,Marcus Cole; Detective Wong; SWAT Team,Normal
41,11,2024-03-18 17:00,Sarah,Command Center,Sarah Morrison; Captain Harris; FBI Team,Normal
42,12,2024-03-18 19:00,Sarah,Arrest Scene,Sarah Morrison; Detective Wong; Suspect; Officers,Normal
43,12,2024-03-18 20:30,Marcus,Precinct,Marcus Cole; Sarah Morrison; Jennifer Blake,Normal
44,12,2024-03-18 22:00,Sarah,Bar,Sarah Morrison; Detective Wong,Normal
45,12,2024-03-19 09:00,Sarah,Court House,Sarah Morrison; DA Peterson; Detective Wong,Normal
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/mystery_novel_scenes.csv
sudo chmod 666 /home/ga/Documents/mystery_novel_scenes.csv

echo "✅ Created scene breakdown CSV with 45 scenes (3 conflicts planted)"
echo "   Conflict 1: Scene 12 - Sarah at two locations simultaneously"
echo "   Conflict 2: Scene 23 - Marcus (POV) not in Characters Present"
echo "   Conflict 3: Scene 31 - Timeline reversal (17:30 after 18:00 in Chapter 8)"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/mystery_novel_scenes.csv > /tmp/calc_manuscript.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_manuscript.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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

# Freeze header row for easier navigation
echo "Freezing header row..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Down
sleep 0.3
# View → Freeze Rows and Columns
safe_xdotool ga :1 key alt+v
sleep 0.5
safe_xdotool ga :1 key r
sleep 0.5

# Return to top
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Manuscript Timeline Validator Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Your mission: Create formulas to detect continuity errors in this"
echo "mystery novel manuscript. There are 3 planted conflicts in 45 scenes."
echo ""
echo "🎯 CONFLICTS TO DETECT:"
echo ""
echo "1. LOCATION CONFLICTS"
echo "   → Character appears in 2+ locations at same timestamp"
echo "   → Use COUNTIFS to find duplicate character+timestamp with different locations"
echo ""
echo "2. MISSING POV CHARACTER"  
echo "   → POV character not listed in 'Characters Present' column"
echo "   → Use SEARCH/FIND/ISNUMBER to check if POV name appears in list"
echo ""
echo "3. TIMELINE REVERSALS"
echo "   → Timestamp goes backward within same chapter"
echo "   → Compare current row timestamp with previous row"
echo "   → EXCLUDE 'Flashback' scene types from this check"
echo ""
echo "📝 REQUIRED ACTIONS:"
echo ""
echo "1. Add validation formula columns (e.g., in columns H, I, J)"
echo "2. Create formulas that return 'CONFLICT' or 'OK' or similar"
echo "3. Apply conditional formatting to highlight conflicts (red background)"
echo "4. Add summary statistics showing total conflicts found"
echo ""
echo "💡 FORMULA HINTS:"
echo ""
echo "Location conflict example:"
echo "  =IF(AND(COUNTIFS(\$D:\$D,D2,\$C:\$C,C2)>1, ...),'CONFLICT','OK')"
echo ""
echo "POV presence example:"
echo "  =IF(ISNUMBER(SEARCH(D2,F2)),'OK','MISSING POV')"
echo ""
echo "Timeline check example:"
echo "  =IF(AND(B2=B1, C2<C1, G2<>'Flashback'),'TIME CONFLICT','OK')"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"