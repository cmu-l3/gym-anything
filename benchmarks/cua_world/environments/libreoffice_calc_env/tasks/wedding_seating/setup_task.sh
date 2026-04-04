#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Wedding Seating Arrangement Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create guest list CSV file
cat > /home/ga/Documents/wedding_guest_list.csv << 'CSVEOF'
Guest Name,Family/Group,Meal Preference,Table Assignment
Emily Rodriguez,Wedding Party,Vegetarian,
Michael Chen,Wedding Party,Beef,
Sarah Johnson,Wedding Party,Chicken,
David Williams,Wedding Party,Fish,
Jessica Martinez,Wedding Party,Vegetarian,
Christopher Davis,Wedding Party,Beef,
Amanda Thompson,Wedding Party,Chicken,
Matthew Anderson,Wedding Party,Fish,
Robert Smith,Smith Family,Beef,
Mary Smith,Smith Family,Chicken,
James Smith,Smith Family,Beef,
Patricia Smith,Smith Family,Fish,
Jennifer Smith,Smith Family,Chicken,
Linda Smith,Smith Family,Vegetarian,
William Johnson,Johnson Family,Beef,
Barbara Johnson,Johnson Family,Chicken,
Richard Johnson,Johnson Family,Fish,
Susan Johnson,Johnson Family,Vegetarian,
Joseph Johnson,Johnson Family,Beef,
Carlos Garcia,Garcia Family,Chicken,
Maria Garcia,Garcia Family,Fish,
Antonio Garcia,Garcia Family,Beef,
Rosa Garcia,Garcia Family,Chicken,
Thomas Chen,Chen Family,Vegetarian,
Nancy Chen,Chen Family,Fish,
Daniel Chen,Chen Family,Beef,
Karen Chen,Chen Family,Chicken,
Charles Williams,Williams Family,Beef,
Betty Williams,Williams Family,Chicken,
Steven Williams,Williams Family,Fish,
Dorothy Williams,Williams Family,Vegetarian,
Juan Martinez,Martinez Family,Beef,
Lisa Martinez,Martinez Family,Chicken,
Miguel Martinez,Martinez Family,Fish,
Paul Davis,Davis Family,Vegetarian,
Laura Davis,Davis Family,Beef,
Mark Davis,Davis Family,Chicken,
Luis Rodriguez,Rodriguez Family,Fish,
Anna Rodriguez,Rodriguez Family,Vegetarian,
Carmen Rodriguez,Rodriguez Family,Beef,
Kevin Lee,Lee Family,Chicken,
Michelle Lee,Lee Family,Fish,
Brian Lee,Lee Family,Beef,
George Thompson,Thompson Couple,Vegetarian,
Sandra Thompson,Thompson Couple,Chicken,
Kenneth Anderson,Anderson Couple,Fish,
Donna Anderson,Anderson Couple,Beef,
Edward White,White Couple,Chicken,
Ashley White,White Couple,Vegetarian,
Ryan Miller,Friends,Fish,
Nicole Wilson,Friends,Beef,
Jason Moore,Friends,Chicken,
Samantha Taylor,Friends,Vegetarian,
Brandon Harris,Friends,Fish,
Megan Clark,Friends,Beef,
Justin Lewis,Friends,Chicken,
Rachel Walker,Friends,Fish,
Tyler Hall,Friends,Vegetarian,
Lauren Young,Friends,Beef,
Aaron King,Friends,Chicken,
Kayla Wright,Friends,Fish,
Eric Scott,Friends,Vegetarian,
Brittany Green,Friends,Beef,
Jordan Baker,Friends,Chicken,
CSVEOF

chown ga:ga /home/ga/Documents/wedding_guest_list.csv

# Convert CSV to ODS using LibreOffice headless mode
echo "Converting CSV to ODS..."
su - ga -c "DISPLAY=:1 libreoffice --headless --convert-to ods --outdir /home/ga/Documents /home/ga/Documents/wedding_guest_list.csv > /tmp/convert_csv.log 2>&1" || true
sleep 2

# If conversion succeeded, use ODS, otherwise import CSV directly
if [ -f "/home/ga/Documents/wedding_guest_list.ods" ]; then
    echo "✅ ODS file created successfully"
    OPEN_FILE="/home/ga/Documents/wedding_guest_list.ods"
else
    echo "⚠️ ODS conversion failed, will open CSV directly"
    OPEN_FILE="/home/ga/Documents/wedding_guest_list.csv"
fi

chown ga:ga "$OPEN_FILE" 2>/dev/null || true
chmod 666 "$OPEN_FILE" 2>/dev/null || true

# Launch LibreOffice Calc with the guest list
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore '$OPEN_FILE' > /tmp/calc_wedding_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_wedding_task.log || true
    # Don't exit - let task continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - let task continue
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

# Navigate to cell D3 (first table assignment cell)
echo "Positioning cursor at D3..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down Down
sleep 0.2

echo "=== Wedding Seating Arrangement Task Setup Complete ==="
echo "📋 Guest List Information:"
echo "   • 64 guests total (rows 3-66)"
echo "   • Wedding Party: 8 people (must be Table 1)"
echo "   • Multiple family groups to keep together"
echo "   • Column D: Table Assignment (empty - fill this)"
echo ""
echo "📝 Instructions:"
echo "   1. Assign Wedding Party members to Table 1"
echo "   2. Assign families to tables (keep together, max 8 per table)"
echo "   3. Create summary in F2:G2 with headers"
echo "   4. Add table numbers in column F (1, 2, 3...)"
echo "   5. Add COUNTIF formulas in column G"
echo "   6. Formula example: =COUNTIF(\$D\$3:\$D\$66, F3)"