#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Oral History Archive Validator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with messy interview data (intentionally inconsistent dates)
cat > /home/ga/Documents/oral_history_interviews.csv << 'CSVEOF'
Interviewee Name,Birth Year,Interview Date,Transcription Status,Release Form Signed,Topic Tags,Duration (min)
Margaret Chen,1934,03/15/2023,Complete,Yes,"WWII, Chinatown",47
Robert Williams,1941,2023-05-22,In Progress,Yes,"Steel Mill, Union",63
Dorothy Martinez,1938,January 2023,Complete,No,,38
James Peterson,1929,2022-11-10,Complete,Yes,"Depression, Farming",71
Helen Kowalski,1945,08/03/2023,Not Started,,"Railroad, Immigration",0
Samuel Jackson,1927,2022-08-15,Complete,Yes,"Civil Rights, Teaching",82
Ruth Goldberg,1942,March 2023,Complete,Yes,"Theater, Arts",55
Thomas O'Brien,1936,2023-04-20,In Progress,Yes,,49
Elizabeth Taylor,1939,12/05/2022,Complete,No,"Fashion, Downtown",67
William Anderson,1931,2023-01-30,Complete,Yes,"Military, Veterans",73
CSVEOF

chown ga:ga /home/ga/Documents/oral_history_interviews.csv
chmod 664 /home/ga/Documents/oral_history_interviews.csv

echo "✅ Created oral_history_interviews.csv with messy data"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with interview data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/oral_history_interviews.csv > /tmp/calc_oral_history.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_oral_history.log
    # Don't exit, let task continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, let task continue
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
        # Maximize window for better visibility
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Ensure cursor is at top-left
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Oral History Archive Validator Task Setup Complete ==="
echo ""
echo "📋 TASK OBJECTIVE:"
echo "   Help prepare oral history interviews for state archive submission"
echo ""
echo "📝 YOUR TASKS:"
echo "   1. Create 'Interview Date (Standardized)' column with YYYY-MM-DD format dates"
echo "   2. Create 'Age at Interview' column calculating age from Birth Year"
echo "   3. Create 'Ready for Archive?' column with validation formula checking:"
echo "      - Transcription Status = 'Complete'"
echo "      - Release Form Signed = 'Yes'"
echo "      - Topic Tags is not empty"
echo "      - Interview Date is not empty"
echo "   4. Apply conditional formatting to 'Ready for Archive?' column"
echo "      (Green for YES, Yellow/Orange for NO)"
echo "   5. Sort data: incomplete (NO) first, then by oldest interview date"
echo ""
echo "💡 HINTS:"
echo "   - Text dates like 'January 2023' need conversion (use 1st of month)"
echo "   - Age formula: =YEAR(date) - Birth_Year"
echo "   - Archive formula: =IF(AND(...), \"YES\", \"NO\")"
echo "   - Multi-level sort: Data → Sort (multiple keys)"
echo ""
echo "🎯 GOAL: Prioritize oldest incomplete interviews for urgent preservation"