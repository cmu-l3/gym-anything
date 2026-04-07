#!/bin/bash
echo "=== Setting up biometric_failure_attendance_recovery task ==="

source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming detection
date +%s > /tmp/task_start_time.txt

# Create the incident report on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/gate3_manual_log_20260310.txt << 'EOF'
INCIDENT REPORT: Gate 3 Biometric Scanner Power Failure
DATE: March 10, 2026

The following personnel logged their shift times manually during the outage:

1. Name: Marcus Webb (EMP018)
   Shift: Morning
   Time In: 05:55 AM
   Time Out: 02:05 PM
   
2. Name: Priya Sharma (EMP019)
   Shift: Morning
   Time In: 06:00 AM
   Time Out: [MISSING]
   
3. Name: Lucas Fernandez (EMP020)
   Shift: Morning
   Time In: 05:45 AM
   Time Out: 02:15 PM
   
HR POLICY NOTE: If an operator failed to log their Time Out during a manual punch incident, you must enter the standard shift end time (02:00 PM) to ensure payroll processing is not blocked.
EOF

chown ga:ga /home/ga/Desktop/gate3_manual_log_20260310.txt
chmod 644 /home/ga/Desktop/gate3_manual_log_20260310.txt

echo "Created incident report on Desktop."

# Ensure target employees exist and are active (Standard HRMS seed data ensures this, but verify)
for EMPID in EMP018 EMP019 EMP020; do
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "UPDATE main_users SET isactive=1 WHERE employeeId='${EMPID}';" 2>/dev/null || true
done

# Start Firefox and log into the application
echo "Starting Firefox and navigating to Sentrifugo dashboard..."
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 5

# Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="