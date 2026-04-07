#!/bin/bash
# Setup task: record_patient_payment
# Patient: Maria Santos

echo "=== Setting up record_patient_payment task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure Maria Santos exists in the database.
# We use INSERT IGNORE or standard INSERT with a WHERE NOT EXISTS to guarantee she's available.
echo "Ensuring patient Maria Santos exists..."
freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) SELECT 'Maria', 'Santos', '1982-08-14', 2 FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM patient WHERE ptfname='Maria' AND ptlname='Santos');" 2>/dev/null || true

# Get her patient ID to verify creation
MARIA_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos' LIMIT 1" 2>/dev/null)
echo "Patient Maria Santos ID: $MARIA_ID"

# Record initial counts of relevant financial/billing tables. 
# FreeMED schema versions vary, so we track a few likely tables to detect new records.
PAYREC_COUNT=$(freemed_query "SELECT COUNT(*) FROM payrec" 2>/dev/null || echo "0")
PAYMENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM payment" 2>/dev/null || echo "0")
BILLING_COUNT=$(freemed_query "SELECT COUNT(*) FROM patient_billing" 2>/dev/null || echo "0")

echo "$PAYREC_COUNT" > /tmp/initial_payrec_count
echo "$PAYMENT_COUNT" > /tmp/initial_payment_count
echo "$BILLING_COUNT" > /tmp/initial_billing_count

echo "Initial table counts - payrec: $PAYREC_COUNT, payment: $PAYMENT_COUNT, billing: $BILLING_COUNT"

# Launch FreeMED in Firefox
ensure_firefox_running "http://localhost/freemed/"

# Maximize and focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_payment_start.png

echo ""
echo "=== record_patient_payment task setup complete ==="
echo "Task: Record $35.00 Cash Copay for Maria Santos"
echo "Login: admin / admin"
echo ""