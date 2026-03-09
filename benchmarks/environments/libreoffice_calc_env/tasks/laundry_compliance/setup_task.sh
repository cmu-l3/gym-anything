#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Laundry Compliance Monitor Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with realistic laundry booking data
cat > /home/ga/Documents/laundry_bookings.csv << 'CSVEOF'
Date,TimeSlot,ResidentID,ResidentName,BookingStatus,ActualUse,MinutesUsed,SlotDuration
2024-01-01,09:00-10:30,R101,Alice Chen,Booked,Yes,85,90
2024-01-01,12:00-13:30,R102,Bob Martinez,Booked,No,0,90
2024-01-02,09:00-10:30,R103,Carol Davis,Booked,Yes,105,90
2024-01-02,14:00-15:30,R104,Dana Kim,Booked,Yes,88,90
2024-01-03,10:30-12:00,R101,Alice Chen,Booked,No,0,90
2024-01-03,12:00-13:30,R101,Alice Chen,Booked,Yes,92,90
2024-01-03,13:30-15:00,R101,Alice Chen,Booked,Yes,88,90
2024-01-04,09:00-10:30,R102,Bob Martinez,Booked,No,0,90
2024-01-05,11:00-12:30,R105,Eve Wilson,Booked,Yes,87,90
2024-01-05,14:00-15:30,R106,Frank Brown,Booked,Yes,95,90
2024-01-06,09:00-10:30,R102,Bob Martinez,Booked,Yes,102,90
2024-01-06,13:00-14:30,R107,Grace Lee,Booked,Yes,89,90
2024-01-07,10:00-11:30,R108,Henry Taylor,Booked,Yes,91,90
2024-01-08,09:00-10:30,R103,Carol Davis,Booked,Yes,108,90
2024-01-08,12:00-13:30,R109,Iris Johnson,Booked,Yes,86,90
2024-01-09,14:00-15:30,R110,Jack White,Booked,Yes,90,90
2024-01-10,09:00-10:30,R101,Alice Chen,Booked,Yes,87,90
2024-01-10,11:00-12:30,R102,Bob Martinez,Booked,No,0,90
2024-01-11,10:00-11:30,R103,Carol Davis,Booked,Yes,112,90
2024-01-12,09:00-10:30,R104,Dana Kim,Booked,Yes,85,90
2024-01-12,13:00-14:30,R105,Eve Wilson,Booked,Yes,89,90
2024-01-13,11:00-12:30,R106,Frank Brown,Booked,Partial,75,90
2024-01-14,09:00-10:30,R107,Grace Lee,Booked,Yes,93,90
2024-01-14,14:00-15:30,R102,Bob Martinez,Booked,No,0,90
2024-01-15,10:00-11:30,R108,Henry Taylor,Booked,Yes,88,90
2024-01-16,09:00-10:30,R109,Iris Johnson,Booked,Yes,91,90
2024-01-16,12:00-13:30,R110,Jack White,Booked,Yes,87,90
2024-01-17,11:00-12:30,R101,Alice Chen,Booked,Yes,90,90
2024-01-18,09:00-10:30,R102,Bob Martinez,Booked,Yes,94,90
2024-01-18,13:00-14:30,R103,Carol Davis,Booked,Yes,105,90
2024-01-19,10:00-11:30,R104,Dana Kim,Booked,Yes,86,90
2024-01-20,09:00-10:30,R105,Eve Wilson,Booked,Yes,92,90
2024-01-20,14:00-15:30,R106,Frank Brown,Booked,Yes,88,90
2024-01-21,11:00-12:30,R107,Grace Lee,Booked,Yes,89,90
2024-01-22,09:00-10:30,R108,Henry Taylor,Booked,Yes,95,90
2024-01-22,13:00-14:30,R102,Bob Martinez,Booked,Yes,107,90
2024-01-23,10:00-11:30,R109,Iris Johnson,Booked,Yes,87,90
2024-01-24,09:00-10:30,R110,Jack White,Booked,Yes,91,90
2024-01-24,12:00-13:30,R101,Alice Chen,Booked,No,0,90
2024-01-25,11:00-12:30,R102,Bob Martinez,Booked,Yes,89,90
2024-01-26,09:00-10:30,R103,Carol Davis,Booked,Yes,115,90
2024-01-26,14:00-15:30,R104,Dana Kim,Booked,Yes,88,90
2024-01-27,10:00-11:30,R105,Eve Wilson,Booked,Yes,90,90
2024-01-28,09:00-10:30,R106,Frank Brown,Booked,Yes,86,90
2024-01-29,13:00-14:30,R107,Grace Lee,Booked,Cancelled,0,90
2024-01-29,14:00-15:30,R108,Henry Taylor,Booked,Yes,92,90
2024-01-30,09:00-10:30,R109,Iris Johnson,Booked,Yes,89,90
2024-01-30,11:00-12:30,R110,Jack White,Booked,Yes,88,90
2024-01-31,10:00-11:30,R101,Alice Chen,Booked,Yes,91,90
2024-01-31,13:00-14:30,R102,Bob Martinez,Booked,Yes,90,90
2024-02-01,09:00-10:30,R103,Carol Davis,Booked,Yes,103,90
2024-02-01,12:00-13:30,R104,Dana Kim,Booked,Yes,87,90
2024-02-02,11:00-12:30,R105,Eve Wilson,Booked,Yes,93,90
2024-02-02,14:00-15:30,R106,Frank Brown,Booked,Yes,89,90
2024-02-03,09:00-10:30,R107,Grace Lee,Booked,Yes,88,90
2024-02-03,13:00-14:30,R108,Henry Taylor,Booked,Yes,94,90
2024-02-04,10:00-11:30,R109,Iris Johnson,Booked,Yes,85,90
2024-02-04,14:00-15:30,R110,Jack White,Booked,Yes,92,90
2024-02-05,09:00-10:30,R101,Alice Chen,Booked,Yes,86,90
2024-02-05,12:00-13:30,R102,Bob Martinez,Booked,No,0,90
2024-02-06,11:00-12:30,R103,Carol Davis,Booked,Yes,118,90
2024-02-06,14:00-15:30,R104,Dana Kim,Booked,Yes,89,90
2024-02-07,09:00-10:30,R102,Bob Martinez,Booked,Yes,104,90
2024-02-08,10:00-11:30,R106,Frank Brown,Booked,Yes,91,90
2024-02-08,13:00-14:30,R107,Grace Lee,Booked,Yes,87,90
2024-02-09,09:00-10:30,R108,Henry Taylor,Booked,Yes,90,90
2024-02-09,12:00-13:30,R109,Iris Johnson,Booked,Yes,88,90
2024-02-10,11:00-12:30,R110,Jack White,Booked,Yes,93,90
2024-02-10,14:00-15:30,R101,Alice Chen,Booked,Yes,89,90
2024-02-11,09:00-10:30,R101,Alice Chen,Booked,Yes,92,90
2024-02-11,10:30-12:00,R101,Alice Chen,Booked,Yes,87,90
2024-02-11,12:00-13:30,R101,Alice Chen,Booked,Yes,91,90
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/laundry_bookings.csv
sudo chmod 666 /home/ga/Documents/laundry_bookings.csv

echo "✅ Created laundry_bookings.csv with 71 booking records"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/laundry_bookings.csv > /tmp/calc_laundry_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_laundry_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Laundry Compliance Monitor Task Setup Complete ==="
echo ""
echo "📊 Task Overview:"
echo "  - 71 booking records from 10 residents over 6 weeks"
echo "  - Multiple policy violations present in data"
echo ""
echo "📝 Your Mission:"
echo "  1. Create 'Compliance Summary' sheet"
echo "  2. Calculate metrics: bookings, no-shows, no-show rate, overtime, violation score"
echo "  3. Apply conditional formatting to highlight violators"
echo "  4. Sort by violation score (worst offenders first)"
echo "  5. Add recommendations column"
echo ""
echo "🎯 Key Formulas Needed:"
echo "  - COUNTIF for aggregation"
echo "  - No-show rate = (NoShows / TotalBookings) * 100"
echo "  - Violation score = (NoShowRate * 0.5) + (OvertimeRate * 0.3) + (MultiSlotDays * 5)"
echo ""
echo "⚠️  Remember: No-shows exclude cancelled bookings!"