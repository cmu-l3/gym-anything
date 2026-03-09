#!/bin/bash
set -e

echo "=== Setting up DDD Event Storming Task ==="

# 1. Ensure directories exist
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the Transcript file with strict legend
cat > /home/ga/Desktop/storming_transcript.txt << 'EOF'
=== EVENT STORMING WORKSHOP TRANSCRIPT: LIBRARY LOAN SYSTEM ===

INSTRUCTIONS:
Digitize this workshop output into Diagrams.net.
You MUST use the EXACT HEX COLOR CODES defined in the Legend below for each element type.
Standard Rectangle shapes are acceptable for all elements.
Connect elements with arrows in the order listed (Left to Right).

=== LEGEND (STRICT COLOR REQUIREMENTS) ===
[Type]              [Color]      [Hex Code]   [Description]
Domain Event        Orange       #FF9900      Something that happened (Past Tense)
Command             Blue         #0099FF      User intent/action (Imperative)
Aggregate           Yellow       #FFFF99      Business object/Entity
Policy              Purple       #CC00CC      Business Rule/Process Logic
External System     Pink         #FFCCE6      Third-party system
Read Model          Green        #CCFFCC      Data view for user
User/Actor          White        #FFFFFF      Person performing action

=== PROCESS FLOW (LEFT TO RIGHT) ===

1.  [User/Actor]      Member
2.  [Command]         Scan Library Card
3.  [System]          Identity Provider
4.  [Event]           Member Authenticated
5.  [Command]         Checkout Book
6.  [Aggregate]       Loan
7.  [Event]           Book Checked Out
8.  [Policy]          Whenever Book Checked Out
9.  [Command]         Update Inventory
10. [System]          Inventory DB
11. [Event]           Inventory Decremented
12. [Read Model]      Member Loan History

--- (Time passes: 2 weeks later) ---

13. [User/Actor]      Librarian
14. [Command]         Return Book
15. [Aggregate]       Loan
16. [Event]           Book Returned
17. [Policy]          If Return Date > Due Date
18. [Command]         Apply Overdue Fine
19. [Event]           Fine Applied

EOF
chown ga:ga /home/ga/Desktop/storming_transcript.txt

# 3. Create a blank draw.io diagram file to start with
# This ensures the agent has a file to open immediately
cat > /home/ga/Diagrams/library_event_storming.drawio << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="Electron" modified="2024-01-01T00:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/26.0.9 Chrome/120.0.6099.109 Electron/28.1.0 Safari/537.36" version="26.0.9" etag="xyz" type="device">
  <diagram id="ProcessFlow" name="Page-1">
    <mxGraphModel dx="1422" dy="798" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XML
chown ga:ga /home/ga/Diagrams/library_event_storming.drawio

# 4. Record initial state
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Diagrams/library_event_storming.drawio > /tmp/initial_mtime.txt

# 5. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/library_event_storming.drawio > /tmp/drawio.log 2>&1 &"

# 6. Wait for window and dismiss update dialogs
echo "Waiting for window..."
sleep 5
for i in {1..5}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 2
done

# Aggressively dismiss update dialog if it appears
# (Common issue in draw.io automation)
for i in {1..10}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Open the transcript file for the agent to see
su - ga -c "DISPLAY=:1 xdg-open /home/ga/Desktop/storming_transcript.txt &"
sleep 2
# Tile windows? No, just let agent manage windows, but ensure draw.io is focused
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="