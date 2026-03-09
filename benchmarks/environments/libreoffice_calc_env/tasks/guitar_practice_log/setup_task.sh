#!/bin/bash
# set -euo pipefail

echo "=== Setting up Guitar Practice Log Task ==="

source /workspace/scripts/task_utils.sh

# Create messy practice log CSV with inconsistent time formats
cat > /home/ga/Documents/practice_notes_raw.csv << 'CSVEOF'
Date,Activity,Time,Difficulty
1/8/2024,Bar chords practice,45 min,4
1/9/2024,Wonderwall - verse,about an hour,3
,Chord transitions (G-C-D),20,4
1/11/2024,Fingerpicking pattern,1:15,5
1/12/2024,Bar chords again,30 min,4
1/13/2024,Blackbird intro,1 hr,5
1/14/2024,Strumming patterns,25,2
1/15/2024,Bar chords,15,4
1/16/2024,Wonderwall - full song,90,3
,Scales practice,30,
1/18/2024,Chord transitions,45 min,4
1/19/2024,Fingerpicking,20,5
1/20/2024,Blackbird middle section,1:30,5
1/21/2024,Bar chords,25 min,4
,Jam session,60,2
CSVEOF

# Set ownership
chown ga:ga /home/ga/Documents/practice_notes_raw.csv
chmod 666 /home/ga/Documents/practice_notes_raw.csv

echo "✅ Created practice_notes_raw.csv with messy data"

# Launch LibreOffice Calc
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore > /tmp/calc_practice_log.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_practice_log.log || true
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

echo "=== Guitar Practice Log Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Open File → Open → /home/ga/Documents/practice_notes_raw.csv"
echo "  2. Clean time data: Convert all time entries to numeric minutes"
echo "     - '45 min' → 45"
echo "     - '1 hr' or 'about an hour' → 60"
echo "     - '1:15' → 75"
echo "     - '1:30' → 90"
echo "  3. Fill missing dates (use week context: Week 1 = Jan 8-14, Week 2 = Jan 15-21)"
echo "  4. Fill missing difficulty ratings (use 3 as default)"
echo "  5. Add summary section below data:"
echo "     - Week 1 Total: =SUM(...)"
echo "     - Week 2 Total: =SUM(...)"
echo "     - Overall Total: =SUM(...)"
echo "     - Average Session: =AVERAGE(...)"
echo "     - Average Difficulty: =AVERAGE(...)"
echo "  6. Identify priorities: Add column with formula"
echo "     =IF(AND(difficulty>=4, time<30), \"HIGH PRIORITY\", \"\")"
echo "  7. Add conditional formatting to highlight priorities"
echo "  8. Create instructor recommendations section"
echo "  9. Save as: guitar_practice_log.ods"
echo ""
echo "💡 Hint: Use Find & Replace (Ctrl+H) to remove text like 'min' and 'hr'"