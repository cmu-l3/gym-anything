#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up dc_metro_transit_map task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/dc_metro_map.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/dc_metro_map.png 2>/dev/null || true

# Create the reference data file
cat > /home/ga/Desktop/wmata_metro_lines.txt << 'TEXTEOF'
WASHINGTON DC METRO (WMATA) - REFERENCE DATA
============================================

INSTRUCTIONS:
Draw these lines using the specified colors. Connect stations in order.
Stations marked [INTERCHANGE] are where multiple lines meet.

1. RED LINE (Color: #BF0D3E)
   Shady Grove -> Bethesda -> Dupont Circle -> Farragut North -> Metro Center [INTERCHANGE] -> Gallery Place [INTERCHANGE] -> Union Station -> Fort Totten [INTERCHANGE] -> Silver Spring -> Glenmont

2. ORANGE LINE (Color: #ED8B00)
   Vienna -> Ballston -> Rosslyn [INTERCHANGE] -> Foggy Bottom -> Farragut West -> Metro Center [INTERCHANGE] -> Federal Triangle -> Smithsonian -> L'Enfant Plaza [INTERCHANGE] -> Eastern Market -> Stadium-Armory -> New Carrollton

3. SILVER LINE (Color: #919D9D)
   Ashburn -> Tysons -> Ballston -> Rosslyn [INTERCHANGE] -> Foggy Bottom -> Farragut West -> Metro Center [INTERCHANGE] -> Federal Triangle -> Smithsonian -> L'Enfant Plaza [INTERCHANGE] -> Eastern Market -> Stadium-Armory -> Largo

4. BLUE LINE (Color: #009CDE)
   Franconia-Springfield -> Pentagon [INTERCHANGE] -> Arlington Cemetery -> Rosslyn [INTERCHANGE] -> Foggy Bottom -> Farragut West -> Metro Center [INTERCHANGE] -> Federal Triangle -> Smithsonian -> L'Enfant Plaza [INTERCHANGE] -> Capitol South -> Eastern Market -> Stadium-Armory -> Largo

5. YELLOW LINE (Color: #FFD100)
   Huntington -> Pentagon [INTERCHANGE] -> L'Enfant Plaza [INTERCHANGE] -> Archives -> Gallery Place [INTERCHANGE] -> Mt Vernon Sq

6. GREEN LINE (Color: #00B140)
   Branch Ave -> Anacostia -> Navy Yard -> L'Enfant Plaza [INTERCHANGE] -> Archives -> Gallery Place [INTERCHANGE] -> Mt Vernon Sq -> Fort Totten [INTERCHANGE] -> College Park -> Greenbelt

TEXTEOF

chown ga:ga /home/ga/Desktop/wmata_metro_lines.txt
chmod 644 /home/ga/Desktop/wmata_metro_lines.txt
echo "Reference file created: /home/ga/Desktop/wmata_metro_lines.txt"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 5

# Maximize the window for consistent layout
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog to get a blank canvas (Escape key)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify draw.io is running
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running and ready."
else
    echo "Warning: draw.io may not have started properly."
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== dc_metro_transit_map setup completed ==="