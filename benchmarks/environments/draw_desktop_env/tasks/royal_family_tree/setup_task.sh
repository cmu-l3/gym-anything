#!/bin/bash
# Do NOT use set -e to prevent early exit on non-critical errors

echo "=== Setting up royal_family_tree task ==="

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
rm -f /home/ga/Desktop/royal_family_tree.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/royal_family_tree.png 2>/dev/null || true
rm -f /home/ga/Desktop/windsor_family_data.csv 2>/dev/null || true

# Create the Data CSV file
cat > /home/ga/Desktop/windsor_family_data.csv << 'CSVEOF'
ID,Name,BirthYear,Gender,ParentID1,ParentID2,SpouseID
1,Queen Elizabeth II,1926,F,,,2
2,Prince Philip,1921,M,,,1
3,King Charles III,1948,M,1,2,4
4,Camilla Queen Consort,1947,F,,,3
5,Princess Anne,1950,F,1,2,6
6,Sir Timothy Laurence,1955,M,,,5
7,Prince Andrew,1960,M,1,2,8
8,Sarah Ferguson,1959,F,,,7
9,Prince Edward,1964,M,1,2,10
10,Sophie Duchess of Edinburgh,1965,F,,,9
11,Prince William,1982,M,3,,12
12,Catherine Princess of Wales,1982,F,,,11
13,Prince Harry,1984,M,3,,14
14,Meghan Duchess of Sussex,1981,F,,,13
15,Peter Phillips,1977,M,5,,
16,Zara Tindall,1981,F,5,,
17,Princess Beatrice,1988,F,7,8,
18,Princess Eugenie,1990,F,7,8,
19,Lady Louise Windsor,2003,F,9,10,
20,James Viscount Severn,2007,M,9,10,
21,Prince George,2013,M,11,12,
22,Princess Charlotte,2015,F,11,12,
23,Prince Louis,2018,M,11,12,
24,Prince Archie,2019,M,13,14,
25,Princess Lilibet,2021,F,13,14,
CSVEOF

chown ga:ga /home/ga/Desktop/windsor_family_data.csv
echo "Created data file: /home/ga/Desktop/windsor_family_data.csv"

# Record start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io (blank)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_royal.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss the "Create New / Open Existing" dialog to get a blank canvas
# Pressing Escape usually dismisses the modal
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/royal_task_start.png 2>/dev/null || true

echo "=== royal_family_tree setup complete ==="