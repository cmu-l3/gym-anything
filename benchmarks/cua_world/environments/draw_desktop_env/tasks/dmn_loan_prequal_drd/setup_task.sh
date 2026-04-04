#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up dmn_loan_prequal_drd task ==="

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

# Clean up any previous outputs
rm -f /home/ga/Desktop/loan_drd.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/loan_drd.png 2>/dev/null || true

# Create the Business Logic Memo
cat > /home/ga/Desktop/risk_policy_memo.txt << 'TXT'
To: Business Analysis Team
From: Chief Risk Officer
Subject: Logic for Instant Pre-Qualification

Here is the logic for our new automated loan pre-qualification engine. Please model this as a DMN diagram so we can hand it off to the developers.

INPUT DATA:
We collect the following raw data from the applicant:
1. Credit Score (integer)
2. Annual Income (currency)
3. Loan Amount (currency)
4. Monthly Debt (currency)

DECISION LOGIC:

1. Determine "Risk Tier"
   - This depends ONLY on the "Credit Score".
   - Logic: If Score < 600 then High; if 600-700 then Medium; if > 700 then Low.

2. Calculate "DTI Ratio" (Debt-to-Income)
   - This requires "Annual Income" and "Monthly Debt".
   - Formula: Monthly Debt / (Annual Income / 12).

3. Determine "Pre-Qualification Result" (Final Decision)
   - This decision requires the "Risk Tier", the "DTI Ratio", and the requested "Loan Amount".
   - Logic: 
     - REJECT if Risk Tier is High.
     - REJECT if DTI Ratio > 43%.
     - REFER if Loan Amount > $50,000 and Risk Tier is Medium.
     - APPROVE otherwise.

Please create a DRD showing these dependencies.
TXT

chown ga:ga /home/ga/Desktop/risk_policy_memo.txt
chmod 644 /home/ga/Desktop/risk_policy_memo.txt

# Record task start time
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_dmn.log 2>&1 &"

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

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/dmn_task_start.png 2>/dev/null || true

echo "=== Setup complete ==="