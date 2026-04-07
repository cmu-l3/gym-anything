#!/bin/bash
echo "=== Setting up Corporate Training Catalog task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Clean up prior data to ensure pristine state
# ==============================================================================
echo "Cleaning existing training providers and courses..."
sentrifugo_db_root_query "DELETE FROM main_trainingcourses;" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_trainingproviders;" 2>/dev/null || true

# ==============================================================================
# 2. Generate Real-World Document
# ==============================================================================
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/q3_training_vendors.txt << 'EOF'
================================================================
Q3 2026 CORPORATE TRAINING VENDOR ROLLOUT
================================================================

Please configure the following external vendors and their 
contracted courses in the HRMS Training Catalog immediately.

----------------------------------------------------------------
VENDOR 1 DETAILS
----------------------------------------------------------------
Provider Name:   Red Cross Safety Institute
Contact Person:  Jane Doe
Email:           jane.doe@redcross-mock.org
Phone:           555-0192

Courses to Add for Vendor 1:
- Course Name:   Occupational First Aid & CPR
- Duration:      2 Days
- Description:   Mandatory site safety and emergency response.

----------------------------------------------------------------
VENDOR 2 DETAILS
----------------------------------------------------------------
Provider Name:   TechAdvantage Learning
Contact Person:  Alan Turing
Email:           alan.turing@techadvantage-mock.com
Phone:           555-0198

Courses to Add for Vendor 2:
- Course Name:   Advanced Python for Data Science
- Duration:      5 Days
- Description:   Machine learning and data processing pipelines.

- Course Name:   Cloud Architecture Fundamentals
- Duration:      3 Days
- Description:   AWS and Azure infrastructure basics.
================================================================
EOF
chown ga:ga /home/ga/Desktop/q3_training_vendors.txt

# ==============================================================================
# 3. GUI Setup
# ==============================================================================
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 5

# Focus the browser
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Capture initial state evidence
echo "Capturing initial state screenshot..."
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="