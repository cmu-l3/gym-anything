#!/bin/bash
# Setup task: add_patient_coverage

echo "=== Setting up add_patient_coverage task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

echo "Ensuring target patient and insurance company exist in database..."

# 1. Ensure Patient Maria Santos exists
PATIENT_EXISTS=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Maria' AND ptlname='Santos'" 2>/dev/null || echo "0")
if [ "$PATIENT_EXISTS" -eq 0 ]; then
    echo "Creating patient Maria Santos..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Maria', 'Santos', '1985-07-22', 2)" 2>/dev/null || true
fi

# 2. Ensure Insurance Company BlueCross BlueShield exists
INSCO_EXISTS=$(freemed_query "SELECT COUNT(*) FROM insco WHERE insconame='BlueCross BlueShield'" 2>/dev/null || echo "0")
if [ "$INSCO_EXISTS" -eq 0 ]; then
    echo "Creating insurance company BlueCross BlueShield..."
    freemed_query "INSERT INTO insco (insconame, inscoadd1, inscocity, inscostate, inscozip) VALUES ('BlueCross BlueShield', '225 N Michigan Ave', 'Chicago', 'IL', '60601')" 2>/dev/null || true
fi

# 3. Clean any existing coverage matching the target policy to ensure a fresh state
freemed_query "DELETE FROM coverage WHERE covpolicyno='BCB-2024-78432' OR policyno='BCB-2024-78432'" 2>/dev/null || true

# 4. Get Patient ID for initial count
PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos' LIMIT 1" 2>/dev/null)
if [ -n "$PATIENT_ID" ]; then
    INITIAL_COVERAGE_COUNT=$(freemed_query "SELECT COUNT(*) FROM coverage WHERE patient='$PATIENT_ID'" 2>/dev/null || echo "0")
    echo "$INITIAL_COVERAGE_COUNT" > /tmp/initial_coverage_count
    echo "Initial coverage count for Maria Santos (ID $PATIENT_ID): $INITIAL_COVERAGE_COUNT"
else
    echo "0" > /tmp/initial_coverage_count
    echo "WARNING: Could not resolve patient ID for Maria Santos."
fi

# 5. Launch and prepare Firefox
echo "Starting FreeMED web interface..."
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2

# Take initial screenshot showing starting state
take_screenshot /tmp/task_coverage_start.png

echo ""
echo "=== add_patient_coverage task setup complete ==="
echo "Target Patient: Maria Santos"
echo "Target Insurer: BlueCross BlueShield"
echo "Task: Add new primary insurance coverage with Policy BCB-2024-78432"
echo "Login: admin / admin"
echo ""