#!/bin/bash
echo "=== Setting up close_security_incident task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Database Seeding
# We need to ensure the incident exists and is in an OPEN state (status=1 usually)
# We also clear any previous analysis/resolution text to ensure the agent actually types it.

echo "Seeding/Resetting Security Incident..."

# Check if incident exists
INCIDENT_EXISTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT count(*) FROM security_incidents WHERE title='Unauthorized VPN Access from External IP';" 2>/dev/null)

if [ "$INCIDENT_EXISTS" -gt "0" ]; then
    # Reset existing incident
    echo "Resetting existing incident..."
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "UPDATE security_incidents SET 
         status=1, 
         description='On 2025-01-10 at 03:42 UTC, the SIEM detected anomalous VPN connections originating from IP 203.0.113.42. The IP geolocates to an unauthorized region. Multiple employee accounts were accessed sequentially.',
         analysis=NULL,
         remediation=NULL,
         modified=NOW() 
         WHERE title='Unauthorized VPN Access from External IP';" 2>/dev/null || true
else
    # Insert new incident
    echo "Creating new incident..."
    # Note: Using likely column names. If 'analysis'/'remediation' don't exist in this specific version, 
    # they will be ignored by the INSERT if we are careful, but for this task we assume standard Eramba schema.
    # We stick to core fields for the insert.
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "INSERT INTO security_incidents (title, description, status, created, modified) VALUES (
         'Unauthorized VPN Access from External IP', 
         'On 2025-01-10 at 03:42 UTC, the SIEM detected anomalous VPN connections originating from IP 203.0.113.42. The IP geolocates to an unauthorized region. Multiple employee accounts were accessed sequentially.',
         1, 
         DATE_SUB(NOW(), INTERVAL 5 DAY), 
         NOW());" 2>/dev/null || true
fi

# 3. Ensure Firefox is running and logged in
ensure_firefox_eramba "http://localhost:8080/security-incidents/index"
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

# 5. Record Initial State for verifier comparison
INITIAL_STATE=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT status, modified FROM security_incidents WHERE title='Unauthorized VPN Access from External IP';" 2>/dev/null)
echo "$INITIAL_STATE" > /tmp/initial_incident_state.txt

echo "=== Setup complete ==="