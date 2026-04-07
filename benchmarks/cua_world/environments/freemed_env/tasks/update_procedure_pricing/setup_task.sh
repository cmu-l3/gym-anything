#!/bin/bash
# Setup task: update_procedure_pricing
# Pre-populates the database with standard CPT codes and sets the old prices

echo "=== Setting up update_procedure_pricing task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Injecting real CPT codes into the procedure database..."

# First, clean up these specific codes if they exist to ensure a clean state
freemed_query "DELETE FROM cpt WHERE cptcode IN ('99211', '99212', '99213', '99214', '99215');" 2>/dev/null || true

# Insert standard CPT codes with baseline pricing
freemed_query "INSERT INTO cpt (cptcode, cptdescrip, cptprice) VALUES ('99211', 'Office/outpatient visit est patient, basic', '45.00');" 2>/dev/null || true
freemed_query "INSERT INTO cpt (cptcode, cptdescrip, cptprice) VALUES ('99212', 'Office/outpatient visit est patient, straightforward', '75.00');" 2>/dev/null || true
freemed_query "INSERT INTO cpt (cptcode, cptdescrip, cptprice) VALUES ('99213', 'Office/outpatient visit est patient, low complexity', '110.00');" 2>/dev/null || true
freemed_query "INSERT INTO cpt (cptcode, cptdescrip, cptprice) VALUES ('99214', 'Office/outpatient visit est patient, moderate complexity', '160.00');" 2>/dev/null || true
freemed_query "INSERT INTO cpt (cptcode, cptdescrip, cptprice) VALUES ('99215', 'Office/outpatient visit est patient, high complexity', '210.00');" 2>/dev/null || true

# Record initial CPT count for anti-gaming (to detect if agent created duplicates)
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM cpt" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_cpt_count.txt
echo "Initial CPT count: $INITIAL_COUNT"

# Ensure Firefox is running and FreeMED is accessible
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window for visibility
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take an initial screenshot
take_screenshot /tmp/task_setup_start.png

echo ""
echo "=== Setup complete ==="
echo "Target CPT 99213 is set to 110.00"
echo "Target CPT 99214 is set to 160.00"
echo "Login: admin / admin"
echo ""