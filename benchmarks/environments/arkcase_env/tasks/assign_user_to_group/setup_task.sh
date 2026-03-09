#!/bin/bash
set -e
echo "=== Setting up Assign User to Group Task ==="

source /workspace/scripts/task_utils.sh

# Configuration
TARGET_USER="alex_rookie"
TARGET_GROUP="FOIA_Processors"
LDAP_POD="arkcase-ldap-0"
NS="arkcase"

# Ensure Port Forwarding is active for API calls
ensure_portforward
wait_for_arkcase

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Preparing LDAP entities..."

# 1. Create Target Group if not exists
if ! kubectl exec -n "$NS" "$LDAP_POD" -- samba-tool group show "$TARGET_GROUP" >/dev/null 2>&1; then
    echo "Creating group $TARGET_GROUP..."
    kubectl exec -n "$NS" "$LDAP_POD" -- samba-tool group add "$TARGET_GROUP"
else
    echo "Group $TARGET_GROUP already exists."
fi

# 2. Create Target User if not exists
if ! kubectl exec -n "$NS" "$LDAP_POD" -- samba-tool user show "$TARGET_USER" >/dev/null 2>&1; then
    echo "Creating user $TARGET_USER..."
    # Create with random password, we don't need to log in as this user
    kubectl exec -n "$NS" "$LDAP_POD" -- samba-tool user create "$TARGET_USER" "RookiePass123!" --use-username-as-cn
else
    echo "User $TARGET_USER already exists."
fi

# 3. Ensure User is NOT in Group initially
echo "Ensuring clean state (removing user from group if present)..."
if kubectl exec -n "$NS" "$LDAP_POD" -- samba-tool group members "$TARGET_GROUP" | grep -q "$TARGET_USER"; then
    kubectl exec -n "$NS" "$LDAP_POD" -- samba-tool group removemembers "$TARGET_GROUP" "$TARGET_USER"
    echo "Removed $TARGET_USER from $TARGET_GROUP"
fi

# Verify clean state
INITIAL_MEMBERS=$(kubectl exec -n "$NS" "$LDAP_POD" -- samba-tool group members "$TARGET_GROUP")
echo "Initial group members: $INITIAL_MEMBERS"
if echo "$INITIAL_MEMBERS" | grep -q "$TARGET_USER"; then
    echo "CRITICAL ERROR: Failed to remove user from group. Setup failed."
    exit 1
fi

# 4. Trigger LDAP sync in ArkCase (optional but good practice to ensure entities appear)
# We'll just wait a moment; ArkCase syncs periodically or on demand.
# For the purpose of the UI task, usually the UI queries LDAP live or has a short cache.

# 5. Launch Firefox and Login
echo "Launching Firefox..."
# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"
sleep 5

# Auto-login
auto_login_arkcase "https://localhost:9443/arkcase/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target User: $TARGET_USER"
echo "Target Group: $TARGET_GROUP"