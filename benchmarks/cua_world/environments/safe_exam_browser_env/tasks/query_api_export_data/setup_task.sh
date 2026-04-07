#!/bin/bash
echo "=== Setting up query_api_export_data task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files and previous exports
sudo rm -f /tmp/task_start_time.txt /tmp/task_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true
sudo rm -rf /home/ga/api_export 2>/dev/null || true

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Create the API credentials reference file
cat > /home/ga/api_credentials.txt << 'EOF'
SEB Server REST API Credentials
===============================
Base URL: http://localhost:8080
Token Endpoint: http://localhost:8080/oauth/token
Grant Type: password

OAuth2 Client Credentials (send via HTTP Basic Auth):
Client ID: sebAdminClient
Client Secret: sebAdminSecret

Resource Owner Credentials (send as form data):
Username: super-admin
Password: admin

Endpoints to Query:
1. GET /admin-api/v1/institution
2. GET /admin-api/v1/useraccount
3. GET /admin-api/v1/configuration_node

NOTE: If the token endpoint authentication fails via curl, you can use a browser as a fallback.
Log into the SEB Server GUI via Firefox, open Developer Tools (F12) -> Network tab,
inspect an API request, and copy the "Authorization: Bearer <token>" header to use in your curl commands.
EOF

chown ga:ga /home/ga/api_credentials.txt
chmod 644 /home/ga/api_credentials.txt

# Launch Firefox and navigate to SEB Server (for reference and DevTools fallback)
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server to make DevTools extraction easier if the agent chooses that path
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should authenticate with the REST API and export data to ~/api_export/"