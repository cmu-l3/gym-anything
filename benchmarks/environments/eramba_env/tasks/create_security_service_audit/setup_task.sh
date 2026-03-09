#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Security Service Audit task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Record initial audit count to detect new records later
INITIAL_AUDIT_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM security_service_audits;" 2>/dev/null || echo "0")
echo "$INITIAL_AUDIT_COUNT" > /tmp/initial_audit_count.txt
echo "Initial security_service_audits count: $INITIAL_AUDIT_COUNT"

# 3. Ensure the target Security Service exists
SERVICE_EXISTS=$(eramba_db_query "SELECT COUNT(*) FROM security_services WHERE title LIKE '%Email Security Gateway%' AND deleted=0;" 2>/dev/null || echo "0")

if [ "$SERVICE_EXISTS" = "0" ]; then
    echo "Target security service not found. Seeding it now..."
    # Insert the service so the agent has something to audit
    eramba_db_query "INSERT INTO security_services (title, description, objective, audit_metric, audit_criteria, created, modified) VALUES ('Email Security Gateway (Phishing Defense)', 'Cloud-based email security gateway filtering inbound/outbound email traffic for phishing, malware, and spam.', 'Reduce successful phishing attacks by 90%', 'Phishing detection rate', 'Detection rate >= 90%, False positive rate < 5%', NOW(), NOW());" 2>/dev/null || true
fi

# 4. Record the ID of the target service for verification
SERVICE_ID=$(eramba_db_query "SELECT id FROM security_services WHERE title LIKE '%Email Security Gateway%' AND deleted=0 LIMIT 1;" 2>/dev/null || echo "")
echo "$SERVICE_ID" > /tmp/target_service_id.txt

# 5. Launch Firefox and login to Eramba
echo "Starting Firefox..."
ensure_firefox_eramba "http://localhost:8080/security-services/index"
sleep 5

# 6. Maximize window for agent visibility
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Security Service Audit task setup complete ==="