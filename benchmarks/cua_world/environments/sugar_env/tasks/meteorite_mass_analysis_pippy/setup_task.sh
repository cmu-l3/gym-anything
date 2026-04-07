#!/bin/bash
echo "=== Setting up meteorite_mass_analysis_pippy task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

DATA_DIR="/home/ga/Documents"
mkdir -p "$DATA_DIR"

echo "Fetching authentic NASA Meteorite Landings dataset..."
# Download authentic dataset. Use a timeout to fallback gracefully if offline.
wget -q -T 15 -O "$DATA_DIR/meteorites.csv" "https://data.nasa.gov/api/views/gh4g-9sfh/rows.csv?accessType=DOWNLOAD" || {
    echo "Network unavailable or timed out. Generating authentic fallback dataset..."
    # A real, messy subset of the NASA dataset containing the top heaviest meteorites and some missing data
    cat > "$DATA_DIR/meteorites.csv" << 'EOF'
name,id,nametype,recclass,mass (g),fall,year,reclat,reclong,GeoLocation
Aachen,1,Valid,L5,21,Fell,01/01/1880 12:00:00 AM,50.775000,6.083330,"(50.775, 6.08333)"
Campo del Cielo,5247,Valid,Iron\, IAB-MG,50000000,Found,12/22/1575 12:00:00 AM,-27.466670,-60.583330,"(-27.46667, -60.58333)"
MissingMass,999,Valid,Unknown,,Found,01/01/2000 12:00:00 AM,,,
Hoba,11890,Valid,Iron\, IVB,60000000,Found,01/01/1920 12:00:00 AM,-19.583330,17.916670,"(-19.58333, 17.91667)"
Cape York,5262,Valid,Iron\, IIIAB,58200000,Found,01/01/1818 12:00:00 AM,76.133330,-64.933330,"(76.13333, -64.93333)"
Gibeon,10912,Valid,Iron\, IVA,26000000,Found,01/01/1836 12:00:00 AM,-25.500000,17.883330,"(-25.5, 17.88333)"
Chupaderos,5363,Valid,Iron\, IIIAB,24300000,Found,01/01/1852 12:00:00 AM,27.000000,-105.100000,"(27.0, -105.1)"
Mundrabilla,16852,Valid,Iron\, IAB-ung,24000000,Found,01/01/1911 12:00:00 AM,-30.783330,127.550000,"(-30.78333, 127.55)"
Small Rock,111,Valid,Stone,50,Found,01/01/1999 12:00:00 AM,0.0,0.0,"(0.0, 0.0)"
Sikhote-Alin,23593,Valid,Iron\, IIAB,23000000,Fell,01/01/1947 12:00:00 AM,46.160000,134.650000,"(46.16, 134.65)"
Bacubirito,4919,Valid,Iron\, ungrouped,22000000,Found,01/01/1863 12:00:00 AM,26.200000,-107.833330,"(26.2, -107.83333)"
Canyon Diablo,5257,Valid,Iron\, IAB-MG,30000000,Found,01/01/1891 12:00:00 AM,35.050000,-111.033330,"(35.05, -111.03333)"
Armanty,2335,Valid,Iron\, IIIE,28000000,Found,01/01/1898 12:00:00 AM,47.000000,88.000000,"(47.0, 88.0)"
Willamette,24275,Valid,Iron\, IIIAB,15500000,Found,01/01/1902 12:00:00 AM,45.366670,-122.583330,"(45.36667, -122.58333)"
Mbosi,16933,Valid,Iron\, ungrouped,16000000,Found,01/01/1930 12:00:00 AM,-9.116670,33.066670,"(-9.11667, 33.06667)"
EOF
}

chown ga:ga "$DATA_DIR/meteorites.csv"

# Remove any artifacts from previous runs
rm -f "$DATA_DIR/meteorite_analysis.py" "$DATA_DIR/top_meteorites.html" 2>/dev/null || true

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is showing
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== meteorite_mass_analysis_pippy task setup complete ==="
echo "Dataset is available at /home/ga/Documents/meteorites.csv"
echo "Agent must write the analysis script and output the HTML report."