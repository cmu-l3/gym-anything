#!/bin/bash
set -e

echo "=== Setting up IVR Call Flow Design Task ==="

# 1. Create necessary directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the Functional Specification
# This provides the logic the agent must implement
cat > /home/ga/Desktop/ivr_spec.txt << 'EOF'
# FUNCTIONAL SPECIFICATION: COASTAL BANK IVR SYSTEM
# Project: Customer Service Voice Portal (CSVP) v2.0
# Date: 2024-05-15

1.0 ENTRY POINT
   - All calls to 1-800-555-BANK enter here.
   - SYSTEM ACTION: Check "Business Hours" (Mon-Fri, 09:00-17:00 EST).

2.0 GLOBAL GATEKEEPER
   - IF (Current Time is OUTSIDE Business Hours):
       - PLAY PROMPT: "Thank you for calling Coastal Bank. Our offices are currently closed."
       - ACTION: Hangup.
   - IF (Current Time is INSIDE Business Hours):
       - PROCEED to Step 3.0.

3.0 CUSTOMER IDENTIFICATION
   - PLAY PROMPT: "Please enter your 10-digit account number."
   - USER INPUT: Expect 10 digits.
   - VALIDATION LOGIC:
       - IF Input is VALID (Database Check OK):
           - PROCEED to Step 4.0.
       - IF Input is INVALID:
           - CHECK Retry Count.
           - IF Retries < 3:
               - PLAY PROMPT: "We could not find that account. Please try again."
               - LOOP back to "Please enter your 10-digit account number".
           - IF Retries >= 3:
               - PLAY PROMPT: "Maximum attempts exceeded. Transferring to operator."
               - TRANSFER to "General Support Queue".

4.0 MAIN MENU
   - PLAY PROMPT: "Main Menu. Please listen carefully as our options have changed."
   - OPTION 1: "For Account Balance"
       - SYSTEM ACTION: Query Database for Balance.
       - PLAY TTS: "Your current balance is [Amount]."
       - ACTION: Return to Main Menu.
   - OPTION 2: "To Report Fraud or Lost Card"
       - ACTION: Set Priority = HIGH.
       - TRANSFER to "Fraud Prevention Team".
   - OPTION 3: "For Loans and Mortgages"
       - PROCEED to Step 5.0 (Sub-menu).
   - OPTION 0: "To Speak to an Agent"
       - TRANSFER to "General Support Queue".
   - INVALID INPUT:
       - PLAY PROMPT: "Invalid selection."
       - RETURN to Main Menu.

5.0 LOANS SUB-MENU
   - PLAY PROMPT: "Press 1 for Mortgages. Press 2 for Auto Loans."
   - OPTION 1: 
       - TRANSFER to "Mortgage Dept".
   - OPTION 2:
       - TRANSFER to "Consumer Lending Dept".
   - OPTION *:
       - RETURN to Main Menu.
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/ivr_spec.txt

# 3. Clean up previous run artifacts
rm -f /home/ga/Diagrams/banking_ivr.drawio
rm -f /home/ga/Diagrams/exports/banking_ivr.pdf

# 4. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io
# Using the environment's helper script if available to handle updates
if [ -f /usr/local/bin/drawio-launch ]; then
    echo "Launching draw.io via helper..."
    /usr/local/bin/drawio-launch &
else
    echo "Launching draw.io directly..."
    su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox &"
fi

# 6. Wait for window and maximize
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found. Maximizing..."
        DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="