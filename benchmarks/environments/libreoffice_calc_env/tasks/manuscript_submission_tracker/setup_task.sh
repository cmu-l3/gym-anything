#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Manuscript Submission Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy manuscript submission CSV file
cat > /home/ga/Documents/manuscript_submissions_messy.csv << 'CSVEOF'
Title,Publication,Submission Date,Response Date,Status,Genre
The Last Star,Asimov's Science Fiction,2024-01-15,2024-03-20,Rejected,Sci-Fi
Whispers in the Dark,The Magazine of Fantasy & Science Fiction,2024-01-22,2024-04-10,Accept,Horror
Ocean's Memory,Clarkesworld Magazine,2024-02-01,,Pending,Sci-Fi
The Silent Garden,Lightspeed Magazine,2024-02-08,2024-03-15,reject,Fantasy
Breaking Protocol,Analog Science Fiction,2024-02-14,2024-05-30,R,Sci-Fi
Dreams of Fire,Tor.com,2024-02-20,,Submitted,Fantasy
The Copper Key,Strange Horizons,2024-02-28,2024-04-05,Accepted,Fantasy
Echoes,Beneath Ceaseless Skies,2024-03-05,2024-06-12,No thanks,Fantasy
Time's Edge,Uncanny Magazine,2024-03-12,,Waiting,Sci-Fi
The Price of Silence,Nightmare Magazine,2024-03-18,2024-05-20,acc,Horror
Fragments of Tomorrow,Asimov's Science Fiction,2024-03-25,2024-06-10,No,Sci-Fi
The Weaver's Song,Clarkesworld Magazine,2024-04-01,2024-05-15,Accepted,Fantasy
Steel Hearts,Lightspeed Magazine,2024-04-08,,pending,Sci-Fi
The Forgotten Door,The Magazine of Fantasy & Science Fiction,2024-04-15,2024-07-20,Rejected,Fantasy
Shadows Between,Tor.com,2024-04-22,2024-06-30,reject,Horror
The Last Harvest,Strange Horizons,2024-04-29,,Pending,Fantasy
Quantum Echoes,Analog Science Fiction,2024-05-06,2024-08-15,Pass,Sci-Fi
The River's Gift,Beneath Ceaseless Skies,2024-05-13,2024-07-01,Yes,Fantasy
Lost Signals,Uncanny Magazine,2024-05-20,2024-08-25,R,Sci-Fi
The Glass Tower,Asimov's Science Fiction,2024-05-27,,blank,Fantasy
Crimson Dawn,Nightmare Magazine,2024-06-03,2024-08-10,Accepted,Horror
The Architect's Dream,Clarkesworld Magazine,2024-06-10,2024-07-25,reject,Sci-Fi
Burning Sky,Lightspeed Magazine,2024-06-17,,Pending,Fantasy
The Memory Thief,The Magazine of Fantasy & Science Fiction,2024-06-24,2024-09-05,No,Horror
CSVEOF

# Set proper ownership
sudo chown ga:ga /home/ga/Documents/manuscript_submissions_messy.csv
sudo chmod 666 /home/ga/Documents/manuscript_submissions_messy.csv

echo "✅ Created messy manuscript submissions CSV file"
ls -lh /home/ga/Documents/manuscript_submissions_messy.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with manuscript data..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/manuscript_submissions_messy.csv > /tmp/calc_manuscript_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_manuscript_task.log || true
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

# Move to cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Manuscript Submission Tracker Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Standardize Status column (use Find & Replace or manual editing)"
echo "     - Convert: 'reject', 'R', 'No thanks', 'No', 'Pass' → 'Rejected'"
echo "     - Convert: 'Accept', 'acc', 'Yes' → 'Accepted'"
echo "     - Convert: 'Submitted', 'Waiting', 'pending', 'blank' → 'Pending'"
echo "  2. Fix date formatting to be consistent"
echo "  3. Add 'Days to Response' column with formula:"
echo "     =IF(ISBLANK(D2),\"Pending\",DATEDIF(C2,D2,\"D\"))"
echo "  4. Create Publication Summary section with:"
echo "     - Total submissions per publication"
echo "     - Acceptance rate (%)"
echo "     - Average response time (days)"
echo "  5. Calculate overall statistics"
echo "  6. Save as manuscript_submissions_cleaned.ods"
echo ""
echo "💡 Hint: Use COUNTIF, AVERAGEIF, and SUMIF for publication statistics"