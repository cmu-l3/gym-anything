#!/bin/bash
echo "=== Setting up sa_demographics_html task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any pre-existing files to ensure a clean state
rm -f /home/ga/Documents/demographics.py
rm -f /home/ga/Documents/density_report.html

# Generate the real-world dataset CSV with thousands separators
cat > /home/ga/Documents/south_america_demographics.csv << 'EOF'
Country,Population,Area_sq_km
Argentina,"45,773,884","2,780,400"
Bolivia,"12,388,571","1,098,581"
Brazil,"216,422,446","8,515,770"
Chile,"19,629,590","756,102"
Colombia,"52,085,168","1,141,748"
Ecuador,"18,190,484","283,561"
Guyana,"813,834","214,969"
Paraguay,"6,861,524","406,752"
Peru,"34,352,719","1,285,216"
Suriname,"623,236","163,820"
Uruguay,"3,423,108","176,215"
Venezuela,"28,838,499","912,050"
EOF

chown ga:ga /home/ga/Documents/south_america_demographics.csv
chmod 644 /home/ga/Documents/south_america_demographics.csv

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is showing
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot of the initial state
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== sa_demographics_html task setup complete ==="