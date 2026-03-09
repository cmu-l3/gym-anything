#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Revoke Leaked Access Token ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Artifactory is up
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time."
    exit 1
fi

# ==============================================================================
# 1. Generate 'Jenkins-Production' token (SHOULD REMAIN ACTIVE)
# ==============================================================================
echo "Generating Production token..."
PROD_RESP=$(curl -s -X POST \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${ADMIN_USER}" \
    -d "scope=applied-permissions/user" \
    -d "expires_in=3600" \
    -d "description=Jenkins-Production" \
    "${ARTIFACTORY_URL}/artifactory/api/security/token" 2>/dev/null)

PROD_TOKEN=$(echo "$PROD_RESP" | jq -r '.access_token')
PROD_ID=$(echo "$PROD_RESP" | jq -r '.token_id')

if [ -z "$PROD_TOKEN" ] || [ "$PROD_TOKEN" == "null" ]; then
    echo "ERROR: Failed to generate Production token"
    echo "Response: $PROD_RESP"
    exit 1
fi

# Save for verification later
echo "$PROD_TOKEN" > /tmp/prod_token.txt
echo "$PROD_ID" > /tmp/prod_id.txt
chmod 600 /tmp/prod_token.txt

# ==============================================================================
# 2. Generate 'Jenkins-Staging' token (TO BE REVOKED)
# ==============================================================================
echo "Generating Staging token (Target)..."
STAGING_RESP=$(curl -s -X POST \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${ADMIN_USER}" \
    -d "scope=applied-permissions/user" \
    -d "expires_in=3600" \
    -d "description=Jenkins-Staging" \
    "${ARTIFACTORY_URL}/artifactory/api/security/token" 2>/dev/null)

STAGING_TOKEN=$(echo "$STAGING_RESP" | jq -r '.access_token')
STAGING_ID=$(echo "$STAGING_RESP" | jq -r '.token_id')

if [ -z "$STAGING_TOKEN" ] || [ "$STAGING_TOKEN" == "null" ]; then
    echo "ERROR: Failed to generate Staging token"
    echo "Response: $STAGING_RESP"
    exit 1
fi

# Save for verification later
echo "$STAGING_TOKEN" > /tmp/staging_token.txt
echo "$STAGING_ID" > /tmp/staging_id.txt
chmod 600 /tmp/staging_token.txt

echo "Tokens generated successfully."

# ==============================================================================
# 3. Create hint file for the agent
# ==============================================================================
cat > /home/ga/leaked_token_info.txt <<EOF
SECURITY INCIDENT REPORT
========================
Severity: HIGH
Incident ID: SEC-2024-001

Leaked Token Detected: "Jenkins-Staging"
Token ID Reference: ${STAGING_ID}

ACTION REQUIRED:
1. Revoke this token immediately via the Administration panel.
2. Do NOT revoke "Jenkins-Production" or any other tokens.
EOF

chown ga:ga /home/ga/leaked_token_info.txt

# ==============================================================================
# 4. Prepare Browser
# ==============================================================================
# Start Firefox and perform login to save time/focus on the revocation task
echo "Launching Firefox and logging in..."
ensure_firefox_running "${ARTIFACTORY_URL}/ui/login"
sleep 5

# Automate login
navigate_to "${ARTIFACTORY_URL}/ui/login"
sleep 5

# Type credentials
DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
DISPLAY=:1 xdotool key Return

# Wait for dashboard
sleep 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="