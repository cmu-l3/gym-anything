#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Raffle Ticket Validator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the raffle sales CSV with intentional issues
cat > /home/ga/Documents/raffle_sales_raw.csv << 'CSVEOF'
Seller Name,Tickets Sold,Money Collected,Date Submitted
Rodriguez,0001-0078,156.00,2024-03-10
Johnson,0050-0075,52.00,2024-03-11
Patel,0079-0099; 0150-0193,130.00,2024-03-11
Martinez,0067; 0100-0120,46.00,2024-03-12
Chen,0300-0324,50.00,2024-03-10
O'Brien,0200-0251,104.00,2024-03-12
Thompson,0252-0276,50.00,2024-03-11
Wilson,0277,2.00,2024-03-13
Davis,,25.00,2024-03-12
Chen,0300-0324,50.00,2024-03-13
Lee,0350-0295,30.00,2024-03-11
Garcia,0400-0455,112.00,2024-03-12
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/raffle_sales_raw.csv
sudo chmod 666 /home/ga/Documents/raffle_sales_raw.csv

echo "✅ Created raffle sales data CSV with intentional issues"
ls -lh /home/ga/Documents/raffle_sales_raw.csv

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc with raffle data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/raffle_sales_raw.csv > /tmp/calc_raffle_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_raffle_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Raffle Ticket Validator Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "  - 12 sellers submitted raffle ticket sales data"
echo "  - Data has duplicates, invalid ranges, and missing entries"
echo "  - Tickets are numbered 0001-0500"
echo ""
echo "🎯 Your Mission:"
echo "  1. Add 'Ticket Count' column - parse ranges like '0100-0125' (26 tickets)"
echo "  2. Add 'Duplicate Flag' column - identify overlapping tickets"
echo "  3. Add 'Validation Status' column - flag impossible ranges"
echo "  4. Add 'Top Seller' column - mark top 3 sellers"
echo "  5. Calculate 'Total Verified Tickets' in a summary cell"
echo ""
echo "💡 Known Issues to Find:"
echo "  - Martinez ticket 0067 overlaps with Johnson's range"
echo "  - Chen submitted data twice (rows 5 and 10)"
echo "  - Davis has money but no ticket numbers"
echo "  - Lee has impossible range 0350-0295"
echo ""
echo "✅ Expected verified total: ~387 tickets"