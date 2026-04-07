#!/bin/bash
echo "=== Setting up exit_clearance_workflow_setup task ==="

source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- Clean up prior run artifacts (if any) ---
echo "Cleaning up any prior clearance configurations..."
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
    SET FOREIGN_KEY_CHECKS=0;
    DELETE FROM main_clearancequestions;
    DELETE FROM main_clearanceusers;
    DELETE FROM main_clearancedepartments;
    SET FOREIGN_KEY_CHECKS=1;
" 2>/dev/null || true

# --- Create the directive file on the Desktop ---
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/exit_clearance_directive.txt << 'EOF'
ACME GLOBAL TECHNOLOGIES
Exit Clearance Workflow Directive
=================================
Configure the following in the Sentrifugo HRMS (Separation -> Configurations module):

1. CLEARANCE DEPARTMENTS
   Create these three departments:
   - IT Asset Recovery
   - Financial Settlement
   - Facilities & Access

2. CLEARANCE USERS (APPROVERS)
   Assign the following existing employees as approvers:
   - IT Asset Recovery    -> Kevin Robinson
   - Financial Settlement -> Jessica Liu
   - Facilities & Access  -> Amanda White

3. CLEARANCE QUESTIONS
   Add the following checklist questions to their respective departments:

   IT Asset Recovery:
   - Has the employee returned their company laptop?
   - Have all system access accounts been deactivated?
   - Has the RSA hardware token been returned?

   Financial Settlement:
   - Are there any outstanding travel advances?
   - Has the corporate credit card been cancelled?

   Facilities & Access:
   - Has the building access badge been returned?
   - Has the office key been returned?

Ensure all records are saved and marked as Active.
EOF

chown ga:ga /home/ga/Desktop/exit_clearance_directive.txt
echo "Directive created at ~/Desktop/exit_clearance_directive.txt"

# --- Launch Browser ---
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="