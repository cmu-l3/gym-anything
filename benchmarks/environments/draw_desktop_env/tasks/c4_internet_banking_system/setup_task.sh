#!/bin/bash
set -u

echo "=== Setting up C4 Internet Banking System task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Desktop/c4_banking.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/c4_banking.png 2>/dev/null || true

# Create the requirements document (based on canonical C4 model example)
cat > /home/ga/Desktop/c4_requirements.txt << 'REQEOF'
=================================================================
C4 MODEL ARCHITECTURE SPECIFICATION
Internet Banking System — Levels 1 & 2
=================================================================
Reference: Based on the canonical example from c4model.com

This document specifies the architecture for diagrams that must be created
in draw.io following C4 model notation conventions.

-----------------------------------------------------------------
PAGE 1: SYSTEM CONTEXT DIAGRAM (C4 Level 1)
-----------------------------------------------------------------
Title: "System Context"

PURPOSE: Show the Internet Banking System in its environment.

ELEMENTS:
  1. Personal Banking Customer [Person]
     - "A customer of the bank, with personal bank accounts."
     - Color: Dark blue (#08427B)

  2. Internet Banking System [Software System]
     - "Allows customers to view information about their bank accounts."
     - Color: Blue (#1168BD)

  3. E-mail System [External Software System]
     - "The internal Microsoft Exchange email system."
     - Color: Gray (#999999)

  4. Mainframe Banking System [External Software System]
     - "Stores all of the core banking information."
     - Color: Gray (#999999)

RELATIONSHIPS:
  A. Customer -> Internet Banking System: "Views account balances, makes payments"
  B. Internet Banking System -> E-mail System: "Sends e-mail using"
  C. Internet Banking System -> Mainframe: "Gets account information from"
  D. E-mail System -> Customer: "Sends e-mails to"

-----------------------------------------------------------------
PAGE 2: CONTAINER DIAGRAM (C4 Level 2)
-----------------------------------------------------------------
Title: "Container"

PURPOSE: Zoom into the Internet Banking System to show containers.

ELEMENTS (Internal Containers):
  1. Web Application [Java/Spring MVC]
     - Delivers static content and SPA.
     - Color: Blue (#438DD5)

  2. Single-Page Application [JavaScript/Angular]
     - Provides functionality via web browser.
     - Color: Blue (#438DD5)

  3. Mobile App [Xamarin]
     - Provides limited functionality via mobile device.
     - Color: Blue (#438DD5)

  4. API Application [Java/Spring MVC]
     - Provides functionality via JSON/HTTPS API.
     - Color: Blue (#438DD5)

  5. Database [Oracle Database 12c]
     - Stores user registration info, hashed credentials, etc.
     - Color: Blue (#438DD5)
     - SHAPE: Cylinder / Database

ELEMENTS (External - for context):
  - Personal Banking Customer
  - E-mail System
  - Mainframe Banking System

RELATIONSHIPS (Must include protocols in brackets):
  A. Customer -> Web Application: "Visits [HTTPS]"
  B. Customer -> SPA: "Views balances using"
  C. Customer -> Mobile App: "Views balances using"
  D. Web Application -> SPA: "Delivers to browser"
  E. SPA -> API Application: "Makes API calls to [JSON/HTTPS]"
  F. Mobile App -> API Application: "Makes API calls to [JSON/HTTPS]"
  G. API Application -> Database: "Reads/writes [SQL/TCP]"
  H. API Application -> E-mail System: "Sends e-mail using [SMTP]"
  I. API Application -> Mainframe: "Makes API calls to [XML/HTTPS]"

-----------------------------------------------------------------
OUTPUT FILES:
-----------------------------------------------------------------
  Save as: ~/Desktop/c4_banking.drawio
  Export Page 1 as PNG: ~/Desktop/c4_banking.png
=================================================================
REQEOF

chown ga:ga /home/ga/Desktop/c4_requirements.txt

# Find drawio binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw\|diagram"; then
        echo "  - draw.io window detected after ${i}s"
        break
    fi
    sleep 1
done
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss "Create New / Open Existing" startup dialog with Escape
# This drops the user into a blank diagram, which is a good starting state
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="