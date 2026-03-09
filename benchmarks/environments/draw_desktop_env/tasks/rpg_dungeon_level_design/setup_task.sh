#!/bin/bash
# setup_task.sh for rpg_dungeon_level_design
set -u

echo "=== Setting up RPG Dungeon Level Design Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create the Design Specification File
cat > /home/ga/Desktop/dungeon_design_spec.txt << 'EOF'
DUNGEON DESIGN DOCUMENT: THE SUNKEN CRYPT
=========================================

Overview:
A mid-level dungeon for a party of 4 adventurers.
Theme: Ancient flooded ruins.

GRID UNIT SCALE: 1 unit = 5 feet.

ROOM LIST & LAYOUT:

1. ENTRY HALL (Start)
   - Size: 4x4 units
   - Contents: Player Start point
   - Exits: North to Grand Hall

2. GRAND HALL
   - Size: 4x8 units (Long North-South hall)
   - Description: Main hub. Dark and damp.
   - Exits: 
     - South to Entry Hall
     - West to Armory
     - East to Shrine
     - North to Boss Chamber (LOCKED DOOR - Requires Rusty Key)

3. ARMORY
   - Size: 4x4 units
   - Contents: "Rusty Key" (Required to open Boss door)
   - Exits: East to Grand Hall

4. SHRINE
   - Size: 4x4 units
   - Contents: "Trap" (Spike pit in center)
   - Exits: 
     - West to Grand Hall
     - North to Treasure Vault (Hidden passage)

5. TREASURE VAULT
   - Size: 3x3 units
   - Contents: "Loot" (Gold and magic items)
   - Exits: South to Shrine

6. BOSS CHAMBER
   - Size: 6x6 units
   - Contents: "Boss" (The Rotting King)
   - Exits: South to Grand Hall (Locked)

INSTRUCTIONS FOR LAYOUT ARTIST:
- Draw all rooms as rectangles roughly proportional to sizes.
- Connect rooms with lines/arrows to show valid paths.
- Label all rooms with their names.
- text labels for: Start, Rusty Key, Trap, Loot, Boss, Locked Door.
EOF

chown ga:ga /home/ga/Desktop/dungeon_design_spec.txt
chmod 644 /home/ga/Desktop/dungeon_design_spec.txt

# Ensure draw.io is installed
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

# Launch draw.io
echo "Launching draw.io..."
# We disable updates to prevent popup noise
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected."
        break
    fi
    sleep 1
done

# Wait a bit for the UI to fully render
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss the "Create New / Open Existing" dialog by pressing Escape
# This drops the user into a blank diagram
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="