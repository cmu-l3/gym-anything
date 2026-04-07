#!/bin/bash
echo "=== Setting up volcano_kml_generator task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents

# Remove any pre-existing output files
rm -f /home/ga/Documents/high_stratovolcanoes.kml 2>/dev/null || true

# Generate the realistic global volcanism CSV data
# Contains exactly 7 target stratovolcanoes > 3000m, and 5 distractors
cat > /home/ga/Documents/volcanoes.csv << 'EOF'
Volcano Name,Country,Type,Latitude,Longitude,Elevation
Cotopaxi,Ecuador,Stratovolcano,-0.677,-78.436,5897
Fuji,Japan,Stratovolcano,35.361,138.728,3776
Popocatepetl,Mexico,Stratovolcano,19.023,-98.622,5393
Kilimanjaro,Tanzania,Stratovolcano,-3.065,37.356,5895
Chimborazo,Ecuador,Stratovolcano,-1.467,-78.817,6268
Pico de Teide,Spain,Stratovolcano,28.271,-16.642,3715
Erebus,Antarctica,Stratovolcano,-77.53,167.17,3794
Mauna Loa,United States,Shield volcano,19.475,-155.608,4170
Kilauea,United States,Shield volcano,19.421,-155.287,1222
Mount St. Helens,United States,Stratovolcano,46.2,-122.18,2549
Krakatoa,Indonesia,Caldera,-6.102,105.423,813
Vesuvius,Italy,Stratovolcano,40.821,14.426,1281
EOF

chown -R ga:ga /home/ga/Documents

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Sugar Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch sugar-terminal-activity" &
sleep 10

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="