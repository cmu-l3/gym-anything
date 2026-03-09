#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Insurance Plan Comparison Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create template CSV with insurance plan data
cat > /home/ga/Documents/insurance_plans_template.csv << 'EOF'
Plan Name,Monthly Premium,Annual Deductible,Coinsurance Rate (%),Out-of-Pocket Max,Annual Premium (Formula),Low Use $2000 Total,Medium Use $8000 Total,High Use $25000 Total
Bronze,$280,"$6,000",40%,"$8,500",,,
Silver,$380,"$3,500",30%,"$6,000",,,
Gold,$480,"$1,500",20%,"$4,000",,,
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/insurance_plans_template.csv
sudo chmod 666 /home/ga/Documents/insurance_plans_template.csv

echo "✅ Created insurance plans template CSV"

# Launch LibreOffice Calc with the template
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/insurance_plans_template.csv > /tmp/calc_insurance_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_insurance_task.log || true
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1
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

# Move cursor to first formula cell (F2 - Annual Premium for Bronze)
echo "Positioning cursor at first calculation cell..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column F (Annual Premium column)
safe_xdotool ga :1 key Right Right Right Right Right
sleep 0.2
# Move to row 2 (first data row)
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Insurance Plan Comparison Task Setup Complete ==="
echo ""
echo "📋 TASK: Compare health insurance plans for open enrollment"
echo ""
echo "📊 PLAN DATA (already entered):"
echo "   • Bronze: \$280/mo premium, \$6,000 deductible, 40% coinsurance, \$8,500 OOP max"
echo "   • Silver: \$380/mo premium, \$3,500 deductible, 30% coinsurance, \$6,000 OOP max"
echo "   • Gold: \$480/mo premium, \$1,500 deductible, 20% coinsurance, \$4,000 OOP max"
echo ""
echo "✏️  YOUR TASKS:"
echo "   1. Calculate Annual Premium (column F): monthly premium × 12"
echo "   2. Calculate Low Use scenario (column G): total cost if \$2,000 in medical expenses"
echo "   3. Calculate Medium Use scenario (column H): total cost if \$8,000 in medical expenses"
echo "   4. Calculate High Use scenario (column I): total cost if \$25,000 in medical expenses"
echo ""
echo "💡 FORMULA LOGIC:"
echo "   • Patient pays all costs up to deductible"
echo "   • After deductible: patient pays coinsurance % of remaining costs"
echo "   • Total patient medical cost capped at OOP max (use MIN function)"
echo "   • Total annual cost = Annual Premium + Patient Medical Cost"
echo ""
echo "🎨 BONUS: Apply conditional formatting to highlight cheapest plan in each scenario"
echo ""
echo "⏱️  Cursor positioned at cell F2 (first formula cell). Good luck!"