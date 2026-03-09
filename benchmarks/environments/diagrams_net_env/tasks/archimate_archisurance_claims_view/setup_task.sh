#!/bin/bash
set -e

echo "=== Setting up ArchiMate Architecture Task ==="

# 1. Prepare environment directories
su - ga -c "mkdir -p /home/ga/Diagrams/exports /home/ga/Desktop" 2>/dev/null || true

# 2. Create the requirements specification file
cat > /home/ga/Desktop/archisurance_specs.txt << 'EOF'
ARCHISURANCE CASE STUDY - CLAIMS SYSTEM ARCHITECTURE
===================================================

REQUIREMENTS:
Create an ArchiMate 3.1 Layered View diagram showing the dependencies for the legacy "Home & Away" policy system.

1. VISUAL STANDARDS:
   - Use the "ArchiMate 3.0" shape library in draw.io (do NOT use basic shapes).
   - Arrange in three horizontal layers: Business (top), Application (middle), Technology (bottom).

2. BUSINESS LAYER (Yellow):
   - Actor: "Customer"
   - Service: "Submit Claim"
   - Process: "Claims Administration"
   - Relationships: Customer is assigned to Submit Claim; Submit Claim triggers Claims Administration.

3. APPLICATION LAYER (Blue):
   - Service: "Claims Management Service"
   - Component: "Home & Away Policy Administration"
   - Data Object: "Customer Data"
   - Relationships: 
     - Claims Management Service serves Claims Administration
     - Home & Away Policy Administration realizes Claims Management Service
     - Home & Away Policy Administration accesses (reads/writes) Customer Data

4. TECHNOLOGY LAYER (Green):
   - Device: "Mainframe"
   - System Software: "Policy Database"
   - Relationships:
     - Mainframe hosts/serves Home & Away Policy Administration
     - Policy Database realizes the storage for Customer Data

5. OUTPUTS:
   - Save source: ~/Diagrams/claims_architecture.drawio
   - Export PDF: ~/Diagrams/exports/claims_architecture.pdf
EOF

chown ga:ga /home/ga/Desktop/archisurance_specs.txt
chmod 644 /home/ga/Desktop/archisurance_specs.txt

# 3. Clean up previous runs
rm -f /home/ga/Diagrams/claims_architecture.drawio 2>/dev/null || true
rm -f /home/ga/Diagrams/exports/claims_architecture.pdf 2>/dev/null || true

# 4. Record task start time
date +%s > /tmp/task_start_timestamp

# 5. Launch draw.io
# We launch it to ensure it's ready, but we don't open a file (agent must create new)
echo "Launching draw.io..."
pkill -f drawio 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# 6. Handle Dialogs (Update & Start Screen)
echo "Waiting for draw.io to initialize..."
sleep 5

# Aggressive update dialog dismissal loop
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "update|confirm"; then
        echo "Dismissing update dialog..."
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    fi
    # If we see the main window or splash screen, we're good
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        break
    fi
    sleep 1
done

# Ensure window is maximized if it exists
if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
    DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="