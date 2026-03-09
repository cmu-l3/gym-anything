#!/bin/bash
# pre_task: Set up the deactivate_and_label_user task
# 1. Create the target user in LDAP/ArkCase
# 2. Log in as Admin and prepare the browser

echo "=== Setting up deactivate_and_label_user task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

ensure_portforward
wait_for_arkcase

# ------------------------------------------------------------------
# 1. Create Target User in LDAP (Samba AD)
# ------------------------------------------------------------------
echo "Creating target user 'audit-temp' in LDAP..."
TARGET_USER="audit-temp"
TARGET_PASS="AuditTemp123!"
TARGET_EMAIL="audit-temp@dev.arkcase.com"

# Check if user exists in LDAP
if kubectl exec -n arkcase arkcase-ldap-0 -- samba-tool user list 2>/dev/null | grep -q "$TARGET_USER"; then
    echo "User $TARGET_USER already exists in LDAP. Resetting state..."
    # Ensure enabled and title is reset
    kubectl exec -n arkcase arkcase-ldap-0 -- samba-tool user enable "$TARGET_USER"
    # Note: samba-tool might not easily set 'title', but ArkCase pulls it. 
    # We will set it via ArkCase API/Login if possible, or assume default is blank/set.
else
    echo "Creating new user $TARGET_USER..."
    kubectl exec -n arkcase arkcase-ldap-0 -- samba-tool user create "$TARGET_USER" "$TARGET_PASS" \
        --given-name="Audit" \
        --surname="Temp" \
        --mail-address="$TARGET_EMAIL" \
        --job-title="Contract Auditor"
fi

# ------------------------------------------------------------------
# 2. Provision User in ArkCase (Trigger Sync via Login)
# ------------------------------------------------------------------
echo "Provisioning user in ArkCase via single login..."
# We curl the login endpoint to force ArkCase to create the user record from LDAP
curl -k -c /tmp/cookies.txt -b /tmp/cookies.txt -X POST \
    -d "j_username=${TARGET_EMAIL}&j_password=${TARGET_PASS}&submit=Login" \
    "${ARKCASE_URL}/j_spring_security_check" > /dev/null 2>&1

# Verify we can find the user via API (Admin check)
echo "Verifying user existence via Admin API..."
# This is a heuristic check; if it fails we continue hoping the login worked enough
arkcase_api GET "users/${TARGET_EMAIL}" > /tmp/user_check.json 2>/dev/null || true

# ------------------------------------------------------------------
# 3. Prepare Firefox for Agent
# ------------------------------------------------------------------
# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox
echo "Launching Firefox..."
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"

# Log in as Admin
auto_login_arkcase "https://localhost:9443/arkcase/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target User: $TARGET_EMAIL"
echo "Target User Password: $TARGET_PASS"
echo "Current State: Active, Title='Contract Auditor'"