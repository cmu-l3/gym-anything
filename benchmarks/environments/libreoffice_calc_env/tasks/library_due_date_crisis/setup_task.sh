#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Library Due Date Crisis Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with realistic library checkout data
# Mix of dates to create overdue, urgent, and normal items
# Current date reference: using relative dates from "today"
cat > /home/ga/Documents/library_checkouts.csv << 'EOF'
Title,Type,Checkout Date,Library Branch,Renewals Used,Has Hold
"The Midnight Library",Book,2024-01-05,Main Library,0,No
"Project Hail Mary",Book,2024-01-12,North Branch,1,Yes
"Dune: Part Two",DVD,2024-01-18,Main Library,0,No
"Atomic Habits",Book,2024-01-08,South Branch,2,No
"The Thursday Murder Club",Book,2024-01-15,Main Library,1,No
"Inception",DVD,2024-01-20,North Branch,0,Yes
"Educated",Book,2024-01-03,South Branch,3,No
"The Matrix",DVD,2024-01-22,Main Library,1,No
"Sapiens",Book,2024-01-10,North Branch,0,No
"The Shawshank Redemption",DVD,2024-01-16,South Branch,2,Yes
"Where the Crawdads Sing",Book,2024-01-01,Main Library,2,No
"Interstellar",DVD,2024-01-24,North Branch,0,No
"The Seven Husbands of Evelyn Hugo",Book,2024-01-19,South Branch,0,Yes
"The Godfather",DVD,2024-01-14,Main Library,1,No
"Lessons in Chemistry",Book,2024-01-06,North Branch,1,No
"Parasite",DVD,2024-01-21,South Branch,0,No
"Tomorrow and Tomorrow and Tomorrow",Book,2024-01-11,Main Library,0,No
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/library_checkouts.csv
sudo chmod 666 /home/ga/Documents/library_checkouts.csv

echo "✅ Created library_checkouts.csv with 17 items"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with library data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/library_checkouts.csv > /tmp/calc_library_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_library_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Library Due Date Crisis Task Setup Complete ==="
echo ""
echo "📚 URGENT: Library books need organizing!"
echo ""
echo "📋 Your Tasks:"
echo "  1. Add 'Due Date' column (Checkout Date + loan period by branch)"
echo "     - Main Library: 21 days | North/South Branch: 14 days"
echo "  2. Add 'Days Until Due' column (Due Date - TODAY())"
echo "  3. Add 'Can Renew' column (renewals < 3 AND no holds)"
echo "  4. Add 'Potential Late Fee (if 7 days late)' column"
echo "     - Books: 7 × $0.25 = $1.75 | DVDs: 7 × $1.00 = $7.00"
echo "  5. Add 'Priority' column:"
echo "     - OVERDUE (days < 0)"
echo "     - URGENT (days 0-3)"
echo "     - HIGH (can't renew)"
echo "     - NORMAL (others)"
echo "  6. Apply conditional formatting (red=overdue, yellow=urgent)"
echo "  7. Sort by Priority then Days Until Due"
echo ""
echo "💡 Tip: Use TODAY() for current date calculations!"
echo "💾 Save as: library_organized.ods"