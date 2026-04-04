#!/bin/bash
set -u

echo "=== Setting up Watergate Link Map Task ==="

# 1. Create the dossier file
cat > /home/ga/Desktop/watergate_notes.txt << 'EOF'
WATERGATE INVESTIGATION - CONFIDENTIAL NOTES
Date: June 20, 1972
Subject: Key Players and Connections

ORGANIZATIONS:
1. The White House (Executive Branch)
2. CREEP (Committee for the Re-Election of the President)
3. The Operatives (Burglars and Fixers)

KEY ACTORS & ROLES:
- Richard Nixon: President of the United States (White House)
- H.R. Haldeman: White House Chief of Staff (White House)
- John Ehrlichman: Assistant to the President (White House)
- John Dean: White House Counsel (White House)
- John Mitchell: Director of CREEP, former Attorney General (CREEP)
- Jeb Stuart Magruder: Deputy Director of CREEP (CREEP)
- G. Gordon Liddy: Finance Counsel for CREEP / "Plumber" (Operatives)
- E. Howard Hunt: White House Consultant / "Plumber" (Operatives)
- James McCord: Security Director for CREEP / Burglar (Operatives)

ESTABLISHED CONNECTIONS:
- H.R. Haldeman -> Reported to -> Richard Nixon
- John Ehrlichman -> Reported to -> Richard Nixon
- John Dean -> Reported to -> Richard Nixon
- John Mitchell -> Reported to -> H.R. Haldeman
- Jeb Stuart Magruder -> Reported to -> John Mitchell
- G. Gordon Liddy -> Hired by -> Jeb Stuart Magruder
- E. Howard Hunt -> Partnered with -> G. Gordon Liddy
- James McCord -> Hired by -> G. Gordon Liddy
- John Dean -> Managed cover-up for -> The Operatives
- CREEP -> Paid legal fees for -> The Operatives
EOF

chown ga:ga /home/ga/Desktop/watergate_notes.txt
chmod 644 /home/ga/Desktop/watergate_notes.txt

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous artifacts
rm -f /home/ga/Desktop/watergate_map.drawio
rm -f /home/ga/Desktop/watergate_map.png

# 4. Ensure draw.io is running
if ! pgrep -f "drawio" > /dev/null; then
    echo "Starting draw.io..."
    # Launch with disable-update to prevent popups, no file arg = blank canvas prompt
    su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true drawio --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
            echo "draw.io window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 6. Handle the "Create New / Open Existing" dialog
# We want the agent to start fresh, so we press Escape to dismiss the dialog,
# which results in a blank unsaved diagram.
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="