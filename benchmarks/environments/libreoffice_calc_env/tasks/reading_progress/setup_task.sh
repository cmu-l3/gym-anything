#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Reading Challenge Progress Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create reading log CSV with 18 books spanning January through mid-May
cat > /home/ga/Documents/reading_log.csv << 'CSVEOF'
Date Finished,Book Title,Author,Genre,Pages,Rating
2024-01-08,The Midnight Library,Matt Haig,Fiction,304,4.5
2024-01-15,Atomic Habits,James Clear,Non-Fiction,320,5.0
2024-01-22,Project Hail Mary,Andy Weir,Sci-Fi,476,4.8
2024-01-29,The Silent Patient,Alex Michaelides,Mystery,336,4.2
2024-02-05,Educated,Tara Westover,Non-Fiction,352,4.9
2024-02-12,The Invisible Life of Addie LaRue,V.E. Schwab,Fiction,448,4.3
2024-02-19,Dune,Frank Herbert,Sci-Fi,688,4.7
2024-02-26,The Thursday Murder Club,Richard Osman,Mystery,368,4.4
2024-03-04,Thinking Fast and Slow,Daniel Kahneman,Non-Fiction,499,4.6
2024-03-11,Where the Crawdads Sing,Delia Owens,Fiction,384,4.1
2024-03-18,The Martian,Andy Weir,Sci-Fi,369,4.9
2024-03-25,Big Little Lies,Liane Moriarty,Mystery,460,4.5
2024-04-01,Sapiens,Yuval Noah Harari,Non-Fiction,443,4.8
2024-04-08,The Seven Husbands of Evelyn Hugo,Taylor Jenkins Reid,Fiction,388,4.6
2024-04-22,Recursion,Blake Crouch,Sci-Fi,329,4.4
2024-05-06,Gone Girl,Gillian Flynn,Mystery,432,4.3
2024-05-13,Range,David Epstein,Non-Fiction,352,4.7
2024-05-20,Circe,Madeline Miller,Fiction,400,4.8
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/reading_log.csv
sudo chmod 666 /home/ga/Documents/reading_log.csv

echo "✅ Created reading_log.csv with 18 book entries"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/reading_log.csv > /tmp/calc_reading_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_reading_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
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

# Move to a cell away from data for user to create summary section
# Move to H1 to give space for summary
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key ctrl+Right
sleep 0.2
safe_xdotool ga :1 key Right Right
sleep 0.2

echo "=== Reading Challenge Progress Tracker Setup Complete ==="
echo ""
echo "📚 TASK: Analyze your reading challenge progress"
echo ""
echo "📋 Current State:"
echo "  • 18 books logged (January through mid-May)"
echo "  • Goal: 52 books this year (1 book/week)"
echo "  • Data columns: Date, Title, Author, Genre, Pages, Rating"
echo ""
echo "✅ Required Analysis:"
echo "  1. Calculate current week of year (using TODAY())"
echo "  2. Determine books expected by now vs. actually read"
echo "  3. Calculate average rating"
echo "  4. Project year-end total based on current pace"
echo "  5. Count books by genre (Fiction, Non-Fiction, Sci-Fi, Mystery)"
echo "  6. Add progress status column (IF logic: on track vs behind)"
echo "  7. Apply conditional formatting (green=on track, red=behind)"
echo ""
echo "💡 Hints:"
echo "  • Use TODAY() and WEEKNUM() for date calculations"
echo "  • Use COUNTA() to count books read"
echo "  • Use AVERAGE() for rating"
echo "  • Use COUNTIF() for genre counts"
echo "  • Use IF() for progress status"
echo "  • Format → Conditional Formatting for colors"
echo ""
echo "🎯 Pass threshold: 6/8 criteria (70%)"