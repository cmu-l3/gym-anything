#!/bin/bash
# Setup script for Activate Clinical Decision Rule Task

echo "=== Setting up Activate Clinical Decision Rule Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Configuration
RULE_ID="rule_adult_wt_screen_fu"
RULE_TITLE="Adult Weight Screening and Follow-up"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Ensure Docker containers are running
echo "Checking OpenEMR containers..."
if ! docker ps | grep -q openemr-mysql; then
    echo "ERROR: OpenEMR MySQL container not running!"
    exit 1
fi

# Query initial state of the rule
echo "Checking initial state of clinical decision rule..."
INITIAL_STATE=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT active, passive_alert, patient_reminder FROM clinical_rules WHERE id='$RULE_ID'" 2>/dev/null)

if [ -z "$INITIAL_STATE" ]; then
    echo "Rule '$RULE_ID' not found in database. Checking if clinical_rules table exists..."
    TABLE_EXISTS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SHOW TABLES LIKE 'clinical_rules'" 2>/dev/null)
    
    if [ -z "$TABLE_EXISTS" ]; then
        echo "ERROR: clinical_rules table does not exist!"
        exit 1
    fi
    
    # List available rules for debugging
    echo "Available clinical rules:"
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "SELECT id, active FROM clinical_rules LIMIT 20" 2>/dev/null
fi

echo "Initial rule state: $INITIAL_STATE"

# CRITICAL: Disable the rule before task starts
# This ensures the agent must actually enable it
echo "Disabling the clinical rule to establish known initial state..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "UPDATE clinical_rules SET active=0, passive_alert=0, patient_reminder=0 WHERE id='$RULE_ID'" 2>/dev/null

# Verify the rule is now disabled
DISABLED_STATE=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT active FROM clinical_rules WHERE id='$RULE_ID'" 2>/dev/null)
echo "Rule active state after setup: $DISABLED_STATE"

if [ "$DISABLED_STATE" != "0" ]; then
    echo "WARNING: Could not confirm rule is disabled (state: $DISABLED_STATE)"
fi

# Record initial state for verification
echo "$DISABLED_STATE" > /tmp/initial_rule_state
echo "0" > /tmp/initial_rule_active

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for audit
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved"

echo ""
echo "=== Activate Clinical Decision Rule Task Setup Complete ==="
echo ""
echo "TASK: Activate the '$RULE_TITLE' clinical decision rule"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin / pass)"
echo "  2. Navigate to Administration > Rules"
echo "  3. Find '$RULE_TITLE' in the rules list"
echo "  4. Enable/activate the rule"
echo "  5. Save your changes"
echo ""
echo "Current rule state: DISABLED (active=0)"
echo "Target rule state: ENABLED (active=1)"
echo ""