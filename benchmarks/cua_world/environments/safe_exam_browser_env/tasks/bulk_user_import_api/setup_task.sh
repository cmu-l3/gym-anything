#!/bin/bash
set -e
echo "=== Setting up bulk_user_import_api task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Create working directory and files
mkdir -p /home/ga/Documents

echo "Creating synthetic staff roster..."
cat > /home/ga/Documents/staff_roster.csv << 'EOF'
GivenName,Surname,EmailAddress,LoginID
Alice,Smith,asmith@univ.edu,asmith01
Bob,Johnson,bjohnson@univ.edu,bjohnson02
Charlie,Williams,cwilliams@univ.edu,cwilliams03
Diana,Brown,dbrown@univ.edu,dbrown04
Evan,Davis,edavis@univ.edu,edavis05
EOF

echo "Creating API credentials guide..."
cat > /home/ga/Documents/api_credentials.txt << 'EOF'
SEB Server API & Authentication Info
------------------------------------
URL: http://localhost:8080
Admin Username: super-admin
Admin Password: admin

PRO TIP:
If you cannot find documentation for the SEB Server API endpoints, the best approach is:
1. Open Firefox and navigate to http://localhost:8080
2. Press F12 to open Developer Tools and go to the Network tab
3. Log in and manually create one test user via the web GUI
4. Inspect the exact HTTP POST request (URL, Headers, JSON payload) made by the browser
5. Replicate that request in your Python script (using the requests library)
EOF

chown -R ga:ga /home/ga/Documents

# Record baseline database state
INITIAL_USER_COUNT=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM user;" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

# Launch Firefox and maximize so the agent can use devtools easily
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="