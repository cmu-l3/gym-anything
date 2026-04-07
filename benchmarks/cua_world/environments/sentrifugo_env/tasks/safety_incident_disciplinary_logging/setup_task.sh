#!/bin/bash
echo "=== Setting up safety_incident_disciplinary_logging task ==="

source /workspace/scripts/task_utils.sh

# Wait for application to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the OSHA Inspection Report on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/osha_inspection_report.txt << 'EOF'
OSHA SPOT-INSPECTION INCIDENT REPORT
Facility: Greenfield Biomass Power Plant
Date of Inspection: January 12, 2026

ACTION REQUIRED:
HR/Plant Management must immediately log the following safety violations into the official HRMS Disciplinary tracking system.

INCIDENT 1
Employee: Christopher Lee (EMP014)
Violation Type to Create: OSHA Violation - Minor
Incident Date: 2026-01-12
Description: Failure to wear high-visibility vest in the active loading yard.
Action Taken: Verbal warning issued.

INCIDENT 2
Employee: Andrew Thomas (EMP017)
Violation Type to Create: OSHA Violation - Critical
Incident Date: 2026-01-12
Description: Bypassed lockout/tagout (LOTO) procedure on the primary chipper maintenance hatch.
Action Taken: Immediate 3-day suspension.
EOF

chown ga:ga /home/ga/Desktop/osha_inspection_report.txt
chmod 644 /home/ga/Desktop/osha_inspection_report.txt

# Inject a marker into the Apache access log for anti-gaming verification
echo "--- TASK START ---" | sudo tee -a /var/log/apache2/sentrifugo_access.log > /dev/null

# Ensure Firefox is open and logged into Sentrifugo dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3

# Take initial state screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="