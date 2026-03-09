#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up windsor_family_tree task ==="

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
rm -f /home/ga/Desktop/windsor_family_tree.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/windsor_family_tree.png 2>/dev/null || true

# Create the genealogy data file
cat > /home/ga/Desktop/windsor_genealogy.txt << 'DATAEOF'
HOUSE OF WINDSOR GENEALOGY DATA
===============================

GENERATION 1
------------
1. King George V (1865-1936)
   - Spouse: Mary of Teck (1867-1953)
   - Children: Edward VIII, George VI, Mary, Henry, George, John

GENERATION 2
------------
1. King Edward VIII (1894-1972)
   - Spouse: Wallis Simpson (1896-1986)
   - Children: None (Abdicated 1936)

2. King George VI (1895-1952)
   - Spouse: Elizabeth Bowes-Lyon (1900-2002)
   - Children: Elizabeth II, Margaret

3. Mary, Princess Royal (1897-1965)
4. Prince Henry, Duke of Gloucester (1900-1974)
5. Prince George, Duke of Kent (1902-1942)
6. Prince John (1905-1919)

GENERATION 3
------------
1. Queen Elizabeth II (1926-2022)
   - Spouse: Prince Philip, Duke of Edinburgh (1921-2021)
   - Children: Charles III, Anne, Andrew, Edward

2. Princess Margaret (1930-2002)
   - Spouse: Antony Armstrong-Jones
   - Children: David, Sarah

GENERATION 4
------------
1. King Charles III (1948-Present)
   - Spouse 1: Lady Diana Spencer (1961-1997) -> Children: William, Harry
   - Spouse 2: Camilla Parker Bowles (1947-Present) -> No children together

2. Anne, Princess Royal (1950-Present)
   - Spouse 1: Mark Phillips -> Children: Peter, Zara
   - Spouse 2: Timothy Laurence

3. Prince Andrew, Duke of York (1960-Present)
   - Spouse: Sarah Ferguson (1959-Present) -> Children: Beatrice, Eugenie

4. Prince Edward, Duke of Edinburgh (1964-Present)
   - Spouse: Sophie Rhys-Jones (1965-Present) -> Children: Louise, James

GENERATION 5
------------
1. Prince William, Prince of Wales (1982-Present)
   - Spouse: Catherine Middleton (1982-Present)
   - Children: George (2013), Charlotte (2015), Louis (2018)

2. Prince Harry, Duke of Sussex (1984-Present)
   - Spouse: Meghan Markle (1981-Present)
   - Children: Archie (2019), Lilibet (2021)

3. Peter Phillips (1977-Present)
4. Zara Tindall (1981-Present)
5. Princess Beatrice (1988-Present)
6. Princess Eugenie (1990-Present)
7. Lady Louise Windsor (2003-Present)
8. James, Earl of Wessex (2007-Present)
DATAEOF

chown ga:ga /home/ga/Desktop/windsor_genealogy.txt
chmod 644 /home/ga/Desktop/windsor_genealogy.txt
echo "Created genealogy data file at /home/ga/Desktop/windsor_genealogy.txt"

# Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io
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

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss the startup dialog to create a blank diagram
echo "Dismissing startup dialog (creating blank diagram)..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/windsor_initial.png 2>/dev/null || true

echo "=== windsor_family_tree setup complete ==="