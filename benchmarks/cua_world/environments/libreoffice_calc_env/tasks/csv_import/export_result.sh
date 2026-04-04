#!/bin/bash
# set -euo pipefail

echo "=== Exporting CSV Import Result ==="

# Focus Calc
wid=$(wmctrl -l | grep -i 'LibreOffice Calc' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
    sleep 1
fi

# Save (Ctrl+S)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 2

# Close
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+q" || true
sleep 1

# Check both CSV and ODS
if [ -f "/home/ga/Documents/employees.ods" ]; then
    echo "✅ ODS file saved"
elif [ -f "/home/ga/Documents/employees.csv" ]; then
    echo "⚠️  Original CSV exists but ODS not created"
fi

echo "=== Export Complete ==="
