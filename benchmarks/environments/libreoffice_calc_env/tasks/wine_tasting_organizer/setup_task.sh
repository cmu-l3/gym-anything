#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Wine Tasting Organizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy wine journal CSV with inconsistent data
cat > /home/ga/Documents/wine_journal.csv << 'CSVEOF'
Wine Name,Type,Original Rating,Price,Tasting Notes,Status
Château Margaux 2015,Red,5 stars,$85,Bold tannins excellent structure,Consumed
Oyster Bay Sauvignon Blanc,White,7/10,12,Crisp citrus notes,In Cellar
Veuve Clicquot,Sparkling,Excellent,$45,Perfect for celebrations,In Cellar
Meiomi Pinot Noir,Red,Good,22,Smooth easy drinking,In Cellar
Barefoot Moscato,White,Okay,$8,Too sweet for my taste,Consumed
La Crema Chardonnay,White,8/10,$18,Nice oak balance,In Cellar
Mumm Napa Brut,Sparkling,4 stars,$20,Light refreshing,In Cellar
Apothic Red,Red,6/10,10,Fruit forward,In Cellar
Whispering Angel Rosé,Rosé,Excellent,25,Best rosé ever,Consumed
19 Crimes Red Blend,Red,Poor,$11,Harsh finish,Consumed
Prisoner Red Blend,Red,9/10,$35,Complex layers,In Cellar
Kim Crawford Sauvignon Blanc,White,7/10,15,Tropical notes,In Cellar
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/wine_journal.csv
sudo chmod 666 /home/ga/Documents/wine_journal.csv

echo "✅ Created wine_journal.csv with messy data"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/wine_journal.csv > /tmp/calc_wine_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_wine_task.log || true
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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

# Position cursor at the beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Wine Tasting Organizer Task Setup Complete ==="
echo "📝 Task Instructions:"
echo "  1. Create 'Standardized Rating' column converting all ratings to 1-10 scale"
echo "     - 5-star ratings: multiply by 2"
echo "     - Text: Excellent=9, Good=7, Okay=5, Poor=3"
echo "  2. Clean price data (remove $ symbols, ensure numeric)"
echo "  3. Create 'Value Score' column: rating divided by price"
echo "  4. Calculate average ratings by wine Type (Red, White, Rosé, Sparkling)"
echo "  5. Identify highest-rated and best-value wines"
echo "  6. Filter available wines (Status = 'In Cellar')"
echo ""
echo "📊 Data info: 12 wines with mixed rating formats and inconsistent prices"