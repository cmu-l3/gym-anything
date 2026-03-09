#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Date Format Standardization Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with mixed date formats
# Simulate realistic POS data with format changes:
# - Early January: MM/DD/YYYY format
# - Mid-Late January: DD-MM-YYYY format (after system update)
# - February onward: YYYY-MM-DD format (after second update)

cat > /home/ga/Documents/sales_data_mixed.csv << 'EOF'
Date,Product,Amount,Customer
01/05/2024,Widget A,45.99,John Smith
01/06/2024,Widget B,32.50,Jane Doe
01/07/2024,Widget A,45.99,Bob Johnson
08-01-2024,Widget C,78.25,Alice Williams
09-01-2024,Widget A,45.99,Charlie Brown
10-01-2024,Widget B,32.50,Diana Prince
15-01-2024,Widget D,123.00,Eve Miller
16-01-2024,Widget A,45.99,Frank Castle
20-01-2024,Widget C,78.25,Grace Lee
25-01-2024,Widget B,32.50,Henry Wong
2024-02-01,Widget A,45.99,Ivy Chen
2024-02-05,Widget D,123.00,Jack Ryan
2024-02-08,Widget C,78.25,Karen Page
2024-02-12,Widget B,32.50,Leo Fitz
2024-02-15,Widget A,45.99,Monica Rambeau
2024-02-20,Widget D,123.00,Nick Fury
2024-03-01,Widget C,78.25,Olivia Pope
2024-03-05,Widget A,45.99,Peter Parker
2024-03-10,Widget B,32.50,Quinn Fabray
2024-03-15,Widget D,123.00,Rachel Green
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/sales_data_mixed.csv
sudo chmod 666 /home/ga/Documents/sales_data_mixed.csv

echo "✅ Created sales_data_mixed.csv with mixed date formats"
echo "   - Rows 2-4: MM/DD/YYYY format (01/05/2024)"
echo "   - Rows 5-11: DD-MM-YYYY format (08-01-2024)"
echo "   - Rows 12-21: YYYY-MM-DD format (2024-02-01)"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/sales_data_mixed.csv > /tmp/calc_date_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_date_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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

# Position cursor at A1 (first data cell after header)
echo "Positioning cursor at cell A1..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Date Format Standardization Task Setup Complete ==="
echo ""
echo "📊 SCENARIO:"
echo "   A shop owner's POS system changed date formats twice during Q1."
echo "   The accountant needs all dates in YYYY-MM-DD format for tomorrow's meeting!"
echo ""
echo "📝 TASK:"
echo "   1. Examine Column A - notice the three different date formats"
echo "   2. Convert ALL dates to YYYY-MM-DD format (ISO standard)"
echo "   3. Verify dates sort chronologically (Jan → Feb → Mar)"
echo "   4. Save the file"
echo ""
echo "💡 HINTS:"
echo "   - Use a helper column (Column F or G) to work safely"
echo "   - TEXT(), DATE(), and DATEVALUE() functions are your friends"
echo "   - Test your formula on a few rows before copying to all"
echo "   - Watch out for ambiguous dates: 01/02/2024 could be Jan 2 OR Feb 1!"
echo "   - Final check: Sort by date to ensure chronological order"
echo ""
echo "📈 CURRENT FORMATS IN FILE:"
echo "   • MM/DD/YYYY: 01/05/2024, 01/06/2024, 01/07/2024"
echo "   • DD-MM-YYYY: 08-01-2024, 09-01-2024, 10-01-2024, etc."
echo "   • YYYY-MM-DD: 2024-02-01, 2024-02-05, etc. (already correct!)"