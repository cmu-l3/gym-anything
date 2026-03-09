#!/bin/bash
set -e

echo "=== Setting up C4 Architecture Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 2. Create the Architecture Specification File
# Based on Simon Brown's C4 model example (Big Bank plc)
cat > /home/ga/Desktop/c4_architecture_spec.txt << 'EOF'
ARCHITECTURE SPECIFICATION: BIG BANK PLC INTERNET BANKING
=========================================================

Instructions:
Create a C4 model (System Context and Container levels) for the system described below.
Use the "C4" shape library in diagrams.net.

scope: Internet Banking System

---------------------------------------------------------
LEVEL 1: SYSTEM CONTEXT DIAGRAM (Page 1)
---------------------------------------------------------
Entities:
1. Personal Banking Customer (Person)
   - Description: A customer of the bank, with personal bank accounts.
2. Internet Banking System (Software System)
   - Description: Allows customers to view information about their bank accounts and make payments.
3. Mainframe Banking System (Existing Software System)
   - Description: Stores all of the core banking information about customers, accounts, transactions, etc.
4. E-mail System (Existing Software System)
   - Description: The internal Microsoft Exchange e-mail system.

Relationships:
- Customer -> Internet Banking System: "Views account balances, and makes payments using"
- Internet Banking System -> Mainframe Banking System: "Gets account information from, and makes payments using"
- Internet Banking System -> E-mail System: "Sends e-mail using"
- E-mail System -> Customer: "Sends e-mails to"

---------------------------------------------------------
LEVEL 2: CONTAINER DIAGRAM (Page 2)
---------------------------------------------------------
Scope: Zoom into "Internet Banking System"

Entities inside the boundary:
1. Single-Page Application (Container: JavaScript and Angular)
   - Description: Provides all of the Internet banking functionality to customers via their web browser.
2. Web Application (Container: Java and Spring MVC)
   - Description: Delivers the static content and the Internet banking single page application.
3. API Application (Container: Java and Spring MVC)
   - Description: Provides Internet banking functionality via a JSON/HTTPS API.
4. Database (Container: Oracle Database Schema)
   - Description: Stores user registration information, hashed credentials, access logs, etc.

External Dependencies (same as Context):
- Personal Banking Customer
- Mainframe Banking System
- E-mail System

Relationships:
- Customer -> Web Application: "Visits bigbank.com/ib using [HTTPS]"
- Customer -> Single-Page Application: "Views account balances, and makes payments using"
- Web Application -> Single-Page Application: "Delivers to the customer's web browser"
- Single-Page Application -> API Application: "Makes API calls to [JSON/HTTPS]"
- API Application -> Database: "Reads from and writes to [JDBC]"
- API Application -> Mainframe Banking System: "Makes API calls to [XML/HTTPS]"
- API Application -> E-mail System: "Sends e-mail using [SMTP]"
EOF

# Set permissions for the spec
chown ga:ga /home/ga/Desktop/c4_architecture_spec.txt
chmod 644 /home/ga/Desktop/c4_architecture_spec.txt

# 3. Create a blank starter diagram
# We create this so the file exists and has the correct name, avoiding naming typos by the agent
cat > /home/ga/Diagrams/banking_system_c4.drawio << 'EOF'
<mxfile host="Electron" modified="2024-01-01T00:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/26.0.9 Chrome/120.0.6099.109 Electron/28.1.0 Safari/537.36" etag="Tx7x" version="26.0.9" type="device">
  <diagram id="C5RBs43oDa-KdzZeNtuy" name="Page-1">
    <mxGraphModel dx="1422" dy="828" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

chown ga:ga /home/ga/Diagrams/banking_system_c4.drawio
chmod 664 /home/ga/Diagrams/banking_system_c4.drawio

# 4. Remove any previous outputs
rm -f /home/ga/Diagrams/banking_system_c4.pdf

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/banking_system_c4.drawio > /dev/null 2>&1 &"

# 7. Wait for window and dismiss update dialogs
echo "Waiting for draw.io to load..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window detected."
        break
    fi
    sleep 1
done
sleep 5

# Aggressively dismiss update dialog if it appears
# Attempt 1: Escape key
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
# Attempt 2: Tab to Cancel + Enter
DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
sleep 0.5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="