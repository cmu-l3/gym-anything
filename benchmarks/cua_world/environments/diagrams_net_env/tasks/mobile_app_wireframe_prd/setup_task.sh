#!/bin/bash
set -e
echo "=== Setting up mobile app wireframe task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Diagrams
sudo -u ga mkdir -p /home/ga/Desktop

# Create blank drawio starter file
cat > /home/ga/Diagrams/transit_app_wireframe.drawio << 'DRAWIOEOF'
<mxfile host="app.diagrams.net" agent="draw.io Desktop" version="26.0.9">
  <diagram id="page-1" name="Page-1">
    <mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
DRAWIOEOF
chown ga:ga /home/ga/Diagrams/transit_app_wireframe.drawio

# Create the PRD document
cat > /home/ga/Desktop/transit_app_prd.txt << 'PRDEOF'
===============================================================================
               PRODUCT REQUIREMENTS DOCUMENT (PRD)
               CityTransit GO — Mobile Trip Planning App
               Version 1.3 | Sprint 14 Wireframe Review
===============================================================================

1. OVERVIEW
-----------
CityTransit GO is a mobile application for planning and tracking public
transit trips within the metropolitan area. This document specifies the
wireframe requirements for 5 core screens to be created in draw.io for
the sprint planning review meeting.

Use draw.io's Mockup shape library (or Android/iOS mockup shapes) for
UI components where possible. Each screen should be on its own page in
the .drawio file. Page dimensions should approximate a mobile phone
aspect ratio.

2. SCREEN SPECIFICATIONS
-------------------------

SCREEN 1: HOME
Page name: "Home"
Layout (top to bottom):
  - Status bar area at top (time, battery, signal indicators)
  - App header: "CityTransit GO" centered
  - Search bar with placeholder text "Where are you going?"
  - Primary action button: "Plan Trip" (prominent, full-width, green)
  - Section header: "Recent Trips"
  - List of 3 recent trip cards, each showing:
      * Trip name (e.g., "Home -> Office")
      * Last used date (e.g., "Used yesterday")
  - Bottom tab bar with 4 tabs:
      * Home (active/highlighted)
      * Map
      * Alerts
      * Profile

SCREEN 2: TRIP PLANNER
Page name: "Trip Planner"
Layout (top to bottom):
  - Status bar area
  - Navigation header with back arrow "<-" and title "Plan Your Trip"
  - Input field labeled "From" with placeholder "Enter origin"
  - Input field labeled "To" with placeholder "Enter destination"
  - Horizontal divider line
  - Date/time selector area:
      * Label: "Depart at"
      * Date field showing "Today, Dec 20"
      * Time field showing "8:00 AM"
  - Checkbox or toggle: "Accessible routes only"
  - Primary button: "Search Routes" (full-width, green)

SCREEN 3: ROUTE RESULTS
Page name: "Route Results"
Layout (top to bottom):
  - Status bar area
  - Navigation header with back arrow "<-" and title "Available Routes"
  - Subtitle: "Main St to Airport Terminal 2"
  - 3 route option cards, each containing:
      * Route card 1: "Bus 42 -> Metro Line A", "45 min", "1 transfer"
      * Route card 2: "Express Bus 100", "35 min", "Direct"
      * Route card 3: "Metro Line B -> Bus 77", "55 min", "1 transfer"
  - Bottom tab bar

SCREEN 4: ROUTE DETAIL
Page name: "Route Detail"
Layout (top to bottom):
  - Status bar area
  - Navigation header with back arrow "<-" and title "Bus 42 -> Metro Line A"
  - Summary bar: "45 min total | 1 transfer | Departs 8:05 AM"
  - Vertical timeline/stepper with 4 stops:
      * Stop 1: "8:05 AM — Board Bus 42 at Main St"
      * Stop 2: "8:25 AM — Arrive Central Station"
      * Stop 3: "8:30 AM — Board Metro Line A at Central Station"
      * Stop 4: "8:50 AM — Arrive Airport Terminal 2"
  - Two buttons side by side:
      * "Save Trip" (secondary style)
      * "Start Navigation" (primary, green)

SCREEN 5: ALERTS
Page name: "Alerts"
Layout (top to bottom):
  - Status bar area
  - Header: "Service Alerts"
  - 3 alert cards:
      * Alert 1: "Metro Line A — Delays Expected"
      * Alert 2: "Bus 77 — Route Detour"
      * Alert 3: "Holiday Schedule Reminder"
  - Bottom tab bar (Alerts tab highlighted/active)

3. NAVIGATION FLOWS
--------------------
Document these navigation connections with arrows between screens
(either on each page or on a separate overview/sitemap page):

  Home --["Plan Trip" button]--> Trip Planner
  Trip Planner --["Search Routes" button]--> Route Results
  Route Results --[Tap route card]--> Route Detail
  Home --[Alerts tab]--> Alerts

4. EXPORT REQUIREMENTS
-----------------------
  - Save as: ~/Diagrams/transit_app_wireframe.drawio
  - Export PNG to: ~/Diagrams/transit_app_wireframe.png

===============================================================================
                         END OF PRD
===============================================================================
PRDEOF
chown ga:ga /home/ga/Desktop/transit_app_prd.txt

# Kill any existing draw.io instances
pkill -f "drawio" 2>/dev/null || true
sleep 2

# Launch draw.io with the blank wireframe file
export DISPLAY=:1
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/transit_app_wireframe.drawio > /tmp/drawio.log 2>&1 &"

# Wait for draw.io to start
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw\|diagram"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

sleep 5

# Dismiss update dialogs (common issue)
echo "Attempting to dismiss update dialogs..."
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done
# Try clicking "Cancel" area (approximate) just in case
DISPLAY=:1 xdotool mousemove 960 600 click 1 2>/dev/null || true

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="