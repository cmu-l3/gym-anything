#!/bin/bash
set -e

echo "=== Setting up RPG Dungeon Level Design Task ==="

# 1. Prepare Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. clean up previous runs
rm -f /home/ga/Diagrams/dungeon_map.drawio
rm -f /home/ga/Diagrams/dungeon_map.png
rm -f /tmp/task_start_time

# 3. Create the Level Design Document
cat > /home/ga/Desktop/level_design_doc.txt << 'EOF'
=== LEVEL DESIGN DOCUMENT: THE CRYPT OF SHADOWS ===
Map Scale: 1 grid unit = 5 feet.
Orientation: Top of page is North.

ROOM LIST & LAYOUT:

1. Entry Chamber
   - Location: Southernmost room.
   - Connection: Leads North to the Grand Hall.

2. Grand Hall
   - Location: Central hub, North of Entry Chamber.
   - Contents: Contains a "Fountain" (Use a Blue Circle or labeled Circle).
   - Connections:
     * Leads West to the Armory.
     * Leads East to the Library.
     * Leads North to the Throne Room (Locked Door).

3. Armory
   - Location: West of Grand Hall.
   - Contents: Contains a "Weapon Rack" (Use a Square).
   - Connection: Dead end.

4. Library
   - Location: East of Grand Hall.
   - Connection: Contains a Secret Door leading North to the Hidden Vault.

5. Hidden Vault
   - Location: North of Library (Secret).
   - Contents: Contains the "Gold Key" (Use a Triangle).
   - Note: The Gold Key is required for the Throne Room.

6. Throne Room
   - Location: North of Grand Hall.
   - Contents: Contains the "Crypt Lord" (Use a Star).
   - Connection: Accessible from Grand Hall.

INSTRUCTIONS:
- Use clear Rectangles for rooms. Label them with room names.
- Use Arrows or Lines for connections.
- Place the specified Item Shapes (Circle, Square, Triangle, Star) INSIDE their respective rooms.
- Export to ~/Diagrams/dungeon_map.png
- Save to ~/Diagrams/dungeon_map.drawio
EOF

chown ga:ga /home/ga/Desktop/level_design_doc.txt

# 4. Record start time for anti-gaming
date +%s > /tmp/task_start_time

# 5. Launch Diagrams.net (draw.io)
echo "Launching draw.io..."
if ! pgrep -f "drawio" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox &"
fi

# 6. Wait for window and dismiss potential update dialogs
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Aggressive dialog dismissal (Esc key)
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="