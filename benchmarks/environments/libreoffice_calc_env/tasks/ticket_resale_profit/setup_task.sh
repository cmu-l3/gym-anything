#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Ticket Resale Profit Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with ticket transaction data (with INCORRECT profit formula)
cat > /home/ga/Documents/ticket_resale_data.csv << 'EOF'
Ticket Description,Purchase Price,Purchase Platform,Sale Price,Sale Platform,Old Profit
Taylor Swift Floor Seats,450,StubHub,620,StubHub,170
NBA Finals Upper Bowl,180,Direct,240,Venmo,60
Broadway Hamilton Orchestra,290,StubHub,310,Ticketmaster,20
Concert VIP Package,380,Friend,420,StubHub,40
Sports Playoffs Box,520,StubHub,580,StubHub,60
Theater Balcony,95,Venue,110,Cash,15
Music Festival GA,220,StubHub,200,Ticketmaster,-20
Comedy Show Premium,140,Direct,180,Venmo,40
Opera Front Row,310,StubHub,350,StubHub,40
Basketball Courtside,890,StubHub,980,Ticketmaster,90
Theater Mezzanine,175,Friend,190,Cash,15
Rock Concert Pit,265,StubHub,245,StubHub,-20
EOF

# Set proper permissions
sudo chown ga:ga /home/ga/Documents/ticket_resale_data.csv

# Open CSV in LibreOffice Calc
echo "Launching LibreOffice Calc with ticket data..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/ticket_resale_data.csv > /tmp/calc_ticket_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_ticket_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
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

# Move to cell A1 (home position)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

# Create a comment/note with fee structure instructions
# Insert a new sheet for instructions
safe_xdotool ga :1 key alt+i
sleep 0.3
safe_xdotool ga :1 key h
sleep 0.5

# Type sheet name
safe_xdotool ga :1 type --delay 50 "Fee Structure Guide"
sleep 0.3
safe_xdotool ga :1 key Return
sleep 0.5

# Add fee structure information
safe_xdotool ga :1 type --delay 30 "FEE STRUCTURE FOR TICKET RESALE"
safe_xdotool ga :1 key Return Return
safe_xdotool ga :1 type --delay 30 "PURCHASE FEES:"
safe_xdotool ga :1 key Return
safe_xdotool ga :1 type --delay 30 "- StubHub: 10% of purchase price"
safe_xdotool ga :1 key Return
safe_xdotool ga :1 type --delay 30 "- Direct/Friend/Venue: 0%"
safe_xdotool ga :1 key Return Return
safe_xdotool ga :1 type --delay 30 "SELLING FEES:"
safe_xdotool ga :1 key Return
safe_xdotool ga :1 type --delay 30 "- StubHub: 15% of sale price"
safe_xdotool ga :1 key Return
safe_xdotool ga :1 type --delay 30 "- Ticketmaster: 12% of sale price"
safe_xdotool ga :1 key Return
safe_xdotool ga :1 type --delay 30 "- Venmo/Cash: 0%"
safe_xdotool ga :1 key Return Return
safe_xdotool ga :1 type --delay 30 "PAYMENT PROCESSING:"
safe_xdotool ga :1 key Return
safe_xdotool ga :1 type --delay 30 "- Platform sales (StubHub/Ticketmaster): 2.9%"
safe_xdotool ga :1 key Return
safe_xdotool ga :1 type --delay 30 "- Cash/Venmo: 0%"
sleep 0.5

# Switch back to first sheet with data
safe_xdotool ga :1 key ctrl+Page_Up
sleep 0.5

# Go to home position
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Ticket Resale Profit Tracker Task Setup Complete ==="
echo ""
echo "📊 SCENARIO:"
echo "   You've been tracking ticket resales but just realized your profit"
echo "   calculations are WRONG! You forgot about all the platform fees."
echo ""
echo "🎯 YOUR TASK:"
echo "   1. Add 'Purchase Fee' column (after Purchase Platform)"
echo "      - Formula: =IF(D2=\"StubHub\", C2*0.10, 0)"
echo "   2. Add 'Selling Fee' column (after Sale Platform)"
echo "      - Formula: =IF(F2=\"StubHub\", E2*0.15, IF(F2=\"Ticketmaster\", E2*0.12, 0))"
echo "   3. Add 'Payment Processing Fee' column"
echo "      - Formula: =IF(OR(F2=\"StubHub\", F2=\"Ticketmaster\"), E2*0.029, 0)"
echo "   4. Rename 'Old Profit' to 'True Profit' and fix formula:"
echo "      - New Formula: =E2-C2-G2-H2-I2"
echo "   5. Apply conditional formatting to highlight negative profits RED"
echo ""
echo "💡 TIP: Check the 'Fee Structure Guide' sheet for fee rates!"
echo ""