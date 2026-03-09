#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Plant Propagation Analyzer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with propagation tracking data
# Using dates from past few months for realistic scenario
cat > /home/ga/Documents/propagation_log.csv << 'EOF'
Date Taken,Plant Species,Propagation Method,Status,Days Since Cutting
2024-09-15,Pothos,Water,Rooted,
2024-10-01,Monstera,Soil,Failed,
2024-10-05,Snake Plant,Perlite,Rooted,
2024-10-12,Pothos,Water,Rooted,
2024-10-20,ZZ Plant,Soil,Pending,
2024-10-25,Philodendron,Water,Failed,
2024-11-02,Pothos,Perlite,Rooted,
2024-11-08,Snake Plant,Water,Rooted,
2024-11-15,Monstera,Soil,Rooted,
2024-11-20,ZZ Plant,Perlite,Pending,
2024-11-28,Philodendron,Soil,Failed,
2024-12-05,Pothos,Water,Rooted,
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/propagation_log.csv
sudo chmod 666 /home/ga/Documents/propagation_log.csv

echo "✅ Created propagation_log.csv with sample data"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/propagation_log.csv > /tmp/calc_propagation_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_propagation_task.log || true
    # Don't exit, allow task to continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, allow task to continue
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

# Position cursor at E2 (Days Since Cutting column, first data row)
echo "Positioning cursor..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to E2 (4 right, 1 down)
safe_xdotool ga :1 key Right Right Right Right Down
sleep 0.3

echo "=== Plant Propagation Analyzer Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Calculate 'Days Since Cutting' (Column E):"
echo "   - In E2, enter formula: =TODAY()-A2"
echo "   - Copy formula down to all data rows (E2:E13)"
echo ""
echo "2. Create Summary Analysis Table (start at row 18):"
echo "   - Headers: Propagation Method | Total Attempts | Successful | Success Rate"
echo "   - List methods: Water, Soil, Perlite"
echo ""
echo "3. Use COUNTIF to count total attempts by method:"
echo "   - Example: =COUNTIF(\$C\$2:\$C\$13,\"Water\")"
echo ""
echo "4. Use COUNTIFS to count successful (Rooted) by method:"
echo "   - Example: =COUNTIFS(\$C\$2:\$C\$13,\"Water\",\$D\$2:\$D\$13,\"Rooted\")"
echo ""
echo "5. Calculate Success Rate (Successful ÷ Total):"
echo "   - Format as percentage"
echo ""
echo "6. Apply Conditional Formatting to Status column (D2:D13):"
echo "   - Green background for 'Rooted'"
echo "   - Red background for 'Failed'"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"