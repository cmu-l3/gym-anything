#!/bin/bash
echo "=== Setting up post_billing_writeoff task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Verify patient Thomas Wright exists, create if not
PATIENT=$(freemed_query "SELECT id FROM patient WHERE ptfname='Thomas' AND ptlname='Wright' LIMIT 1" 2>/dev/null)
if [ -z "$PATIENT" ]; then
    echo "Creating patient Thomas Wright..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Thomas', 'Wright', '1980-01-01', 1);" 2>/dev/null || true
    PATIENT=$(freemed_query "SELECT id FROM patient WHERE ptfname='Thomas' AND ptlname='Wright' LIMIT 1" 2>/dev/null)
fi
PATIENT_ID=$(echo "$PATIENT" | cut -f1)
echo "Patient ID: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/target_patient_id

# Add a charge of $8.50 to create a balance (makes it realistic)
CHARGE_EXISTS=$(freemed_query "SELECT COUNT(*) FROM procrec WHERE ppatient=$PATIENT_ID AND proccharge='8.50'" 2>/dev/null || echo "0")
if [ "$CHARGE_EXISTS" -eq "0" ]; then
    echo "Adding $8.50 charge to patient account..."
    freemed_query "INSERT INTO procrec (ppatient, proccharge, proccode, procdate) VALUES ($PATIENT_ID, '8.50', '99211', CURDATE());" 2>/dev/null || true
fi

# Record max IDs for relevant tables (Anti-gaming: ensuring new records are created during task)
MAX_PAYMENT=$(freemed_query "SELECT IFNULL(MAX(id), 0) FROM payment" 2>/dev/null || echo "0")
echo "$MAX_PAYMENT" > /tmp/max_payment_id

MAX_BILLING=$(freemed_query "SELECT IFNULL(MAX(id), 0) FROM billing" 2>/dev/null || echo "0")
echo "$MAX_BILLING" > /tmp/max_billing_id

MAX_PROCREC=$(freemed_query "SELECT IFNULL(MAX(id), 0) FROM procrec" 2>/dev/null || echo "0")
echo "$MAX_PROCREC" > /tmp/max_procrec_id

# Start FreeMED UI
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="
echo "Patient: Thomas Wright"
echo "Task: Post an 8.50 adjustment"