#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Recipe Scaler Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with recipe data
cat > /home/ga/Documents/recipe_original.csv << 'EOF'
Ingredient,Original Amount,Unit
All-Purpose Flour,1.5,cups
Granulated Sugar,0.667,cups
Butter (softened),0.5,cups
Eggs,2,whole
Vanilla Extract,1.5,tsp
Baking Soda,0.75,tsp
Salt,0.5,tsp
Chocolate Chips,1.5,cups
EOF

# Set permissions
sudo chown ga:ga /home/ga/Documents/recipe_original.csv
sudo chmod 644 /home/ga/Documents/recipe_original.csv

echo "✅ Created recipe_original.csv with 8 ingredients"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with recipe data..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/recipe_original.csv > /tmp/calc_recipe_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_recipe_task.log || true
    # Don't exit, continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue
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

# Move cursor to a starting position (cell E1 for scaling factor)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Recipe Scaler Task Setup Complete ==="
echo ""
echo "📋 Recipe Information:"
echo "  • Original recipe: Makes 24 cookies"
echo "  • Target: 75 cookies"
echo "  • Scaling factor: 75/24 = 3.125"
echo ""
echo "📝 Instructions:"
echo "  1. Add column headers for 'Scaled Amount' and 'Practical Amount'"
echo "  2. Create cells for Original Quantity (24) and Target Quantity (75)"
echo "  3. Calculate scaling factor: =Target/Original"
echo "  4. For each ingredient, create formula: =Original_Amount * Scaling_Factor"
echo "  5. For practical amounts, apply rounding:"
echo "     • Eggs: Use ROUNDUP to get whole numbers (can't use 6.25 eggs!)"
echo "     • Other ingredients: Round to practical fractions (0.25 increments)"
echo "  6. Verify that all formulas reference cells (not hardcoded values)"
echo ""
echo "💡 Key Tips:"
echo "  • Use absolute references for scaling factor (e.g., \$E\$2)"
echo "  • Eggs must be rounded UP: ROUNDUP(scaled_value, 0)"
echo "  • The recipe has 8 ingredients - scale all of them"