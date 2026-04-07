#!/bin/bash
# Setup script for gapminder_geography_report task
echo "=== Setting up gapminder_geography_report task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing report
rm -f /home/ga/Documents/development_report.odt 2>/dev/null || true

# Download the real Gapminder dataset
echo "Preparing dataset..."
wget -q -O /home/ga/Documents/gapminder.csv "https://raw.githubusercontent.com/plotly/datasets/master/gapminderDataFiveYear.csv"

# Fallback just in case wget fails (ensure task is still possible)
if [ ! -s /home/ga/Documents/gapminder.csv ]; then
    echo "WARNING: Failed to download full dataset, generating fallback data..."
    cat > /home/ga/Documents/gapminder.csv << 'EOF'
country,continent,year,lifeExp,pop,gdpPercap
Rwanda,Africa,1952,40.0,2534927,249.9097656
Rwanda,Africa,1957,41.5,2822082,283.654763
Rwanda,Africa,2002,43.413,7852401,785.653765
Rwanda,Africa,2007,46.242,8860588,863.0884639
Sweden,Europe,1952,71.86,7124673,8527.844662
Sweden,Europe,1957,72.49,7363802,9911.878226
Sweden,Europe,2002,80.04,8954175,29341.63093
Sweden,Europe,2007,80.884,9031088,33859.74835
EOF
fi

chown ga:ga /home/ga/Documents/gapminder.csv
chmod 644 /home/ga/Documents/gapminder.csv

# Record task start timestamp (anti-gaming)
date +%s > /tmp/gapminder_report_start_ts
chmod 666 /tmp/gapminder_report_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Verify Sugar session is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/gapminder_task_start.png" 2>/dev/null || true

echo "=== gapminder_geography_report task setup complete ==="
echo "Dataset placed at /home/ga/Documents/gapminder.csv"
echo "Agent must extract data, calculate changes, and save ODT report."