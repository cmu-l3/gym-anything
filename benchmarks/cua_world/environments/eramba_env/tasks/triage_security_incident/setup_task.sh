#!/bin/bash
set -e
echo "=== Setting up Triage Security Incident Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Wait for MySQL
echo "Waiting for database..."
for i in {1..30}; do
    if docker exec eramba-db mysqladmin ping -h localhost -u root -peramba_root_pass 2>/dev/null; then
        break
    fi
    sleep 2
done

# 3. Ensure 'Denial of Service' classification exists in taxonomy
# Using generic taxonomy insert if not present
echo "Ensuring Classification exists..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO taxonomy_lookups (model, name, created, modified) 
     SELECT 'SecurityIncident', 'Denial of Service', NOW(), NOW() 
     WHERE NOT EXISTS (SELECT 1 FROM taxonomy_lookups WHERE name='Denial of Service' AND model='SecurityIncident');" 2>/dev/null || true

# 4. Ensure the specific Security Incident exists and is in a 'clean' state (unassigned, unclassified)
echo "Resetting Incident state..."
# First, create if not exists
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO security_incidents (title, description, incident_date, status, created, modified) 
     SELECT 'SIEM Alert: High Volume Traffic', 'Automated alert: 5000 req/sec detected.', NOW(), 1, NOW(), NOW()
     WHERE NOT EXISTS (SELECT 1 FROM security_incidents WHERE title='SIEM Alert: High Volume Traffic');" 2>/dev/null || true

# Then, force update to known 'untriaged' state (NULLs) so we can verify the agent actually did the work
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "UPDATE security_incidents SET 
     classification_id = NULL, 
     severity_id = NULL, 
     owner_id = NULL, 
     modified = NOW() - INTERVAL 1 DAY 
     WHERE title='SIEM Alert: High Volume Traffic';" 2>/dev/null || true

# 5. Launch Firefox to the Security Incidents module
ensure_firefox_eramba "http://localhost:8080/security-incidents/index"

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="