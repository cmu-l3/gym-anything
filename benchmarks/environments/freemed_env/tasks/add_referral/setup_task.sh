#!/bin/bash
# Setup task: add_referral
# Patient: Hobert Wuckert (ID 11) - Synthea-generated patient
# Task: Create referral to orthopedic surgery for knee injury

echo "=== Setting up add_referral task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Verify patient Hobert Wuckert (ID 11)
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=11" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID 11 (Hobert Wuckert) not found!"
    exit 1
fi

# Record initial referral count (FreeMED uses 'referrals' table)
INITIAL=$(freemed_query "SELECT COUNT(*) FROM referrals WHERE patient=11" 2>/dev/null || echo "0")
[ -z "$INITIAL" ] && INITIAL=0
echo "$INITIAL" > /tmp/initial_referral_count
echo "Initial referral count: $INITIAL"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_referral_start.png

echo ""
echo "=== add_referral task setup complete ==="
echo "Task: Create referral to Dr. Kevin Ramirez (Orthopedic Surgery) for Hobert Wuckert (ID=11)"
echo "Reason: Right knee pain and swelling, suspected meniscal tear with joint effusion"
echo "Date: 2025-05-10"
echo "Login: admin / admin"
echo ""
