#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up climate_feedback_loops task ==="

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

# Clean up previous runs
rm -f /home/ga/Desktop/climate_loops.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/climate_loops.png 2>/dev/null || true

# Create the data file with loop definitions
cat > /home/ga/Desktop/feedback_loops_data.txt << 'DATAEOF'
CLIMATE FEEDBACK LOOPS DATA
===========================

CENTRAL VARIABLE:
- Global Mean Temperature

LOOP 1: ICE-ALBEDO FEEDBACK (Reinforcing / Positive Loop)
1. Global Mean Temperature --(-)--> Arctic Sea Ice Extent
   (Higher Temp -> Less Ice)
2. Arctic Sea Ice Extent --(+)--> Planetary Albedo
   (Less Ice -> Less Albedo/Reflection)
3. Planetary Albedo --(-)--> Solar Energy Absorption
   (Less Albedo -> More Absorption)
4. Solar Energy Absorption --(+)--> Global Mean Temperature
   (More Absorption -> Higher Temp)

LOOP 2: PERMAFROST CARBON FEEDBACK (Reinforcing / Positive Loop)
1. Global Mean Temperature --(+)--> Permafrost Thaw Rate
   (Higher Temp -> More Thaw)
2. Permafrost Thaw Rate --(+)--> Atmospheric CO2 & Methane
   (More Thaw -> More GHGs)
3. Atmospheric CO2 & Methane --(+)--> Greenhouse Effect
   (More GHGs -> Stronger Greenhouse Effect)
4. Greenhouse Effect --(+)--> Global Mean Temperature
   (Stronger Greenhouse -> Higher Temp)

LOOP 3: WATER VAPOR FEEDBACK (Reinforcing / Positive Loop)
1. Global Mean Temperature --(+)--> Ocean Evaporation
   (Higher Temp -> More Evaporation)
2. Ocean Evaporation --(+)--> Atmospheric Water Vapor
   (More Evaporation -> More Vapor)
3. Atmospheric Water Vapor --(+)--> Greenhouse Effect
   (More Vapor -> Stronger Greenhouse Effect)
4. Greenhouse Effect --(+)--> Global Mean Temperature
   (Stronger Greenhouse -> Higher Temp)

NOTATION GUIDE:
- Use CURVED lines for connections.
- Label arrows with "+" (change in same direction) or "-" (change in opposite direction).
- Place an "R" icon or text label inside each loop to indicate it is Reinforcing.
DATAEOF

chown ga:ga /home/ga/Desktop/feedback_loops_data.txt
echo "Created data file at /home/ga/Desktop/feedback_loops_data.txt"

# Record start time
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_loops.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Maximize
sleep 5
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Escape creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/loops_task_start.png 2>/dev/null || true

echo "=== Setup complete ==="