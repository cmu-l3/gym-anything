#!/bin/bash
echo "=== Exporting result for reset_locked_user_password ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use Python to verify the final state (Login & Group Check)
# We use the Internal UI API again to verify group membership because OSS REST API is restricted
cat > /tmp/verify_state.py << 'EOF'
import requests
import json
import sys

BASE_URL = "http://localhost:8082/artifactory"
UI_BASE_URL = "http://localhost:8082/ui"
ADMIN_USER = "admin"
ADMIN_PASS = "password"
TARGET_USER = "jmonroe"
TARGET_PASS = "TemporaryFix#2024"
TARGET_GROUP = "backend-devs"

result = {
    "authentication_success": False,
    "group_membership_preserved": False,
    "user_exists": False
}

session = requests.Session()

# 1. Test Authentication with New Password
print(f"Testing login for {TARGET_USER}...")
try:
    auth_resp = requests.get(f"{BASE_URL}/api/system/ping", auth=(TARGET_USER, TARGET_PASS))
    if auth_resp.status_code == 200:
        result["authentication_success"] = True
        print("Authentication successful.")
    else:
        print(f"Authentication failed: HTTP {auth_resp.status_code}")
except Exception as e:
    print(f"Auth check error: {e}")

# 2. Check Group Membership (requires Admin login)
print("Checking group membership...")
try:
    # Admin Login
    login_data = {"user": ADMIN_USER, "password": ADMIN_PASS, "type": "login"}
    login_resp = session.post(f"{UI_BASE_URL}/auth/login", json=login_data, headers={"Content-Type": "application/json"})
    
    if login_resp.status_code == 200:
        # Get User Details
        user_resp = session.get(f"{UI_BASE_URL}/admin/security/users/{TARGET_USER}")
        if user_resp.status_code == 200:
            result["user_exists"] = True
            user_data = user_resp.json()
            groups = user_data.get("groups", [])
            print(f"User groups: {groups}")
            if TARGET_GROUP in groups:
                result["group_membership_preserved"] = True
        else:
            print(f"User not found (HTTP {user_resp.status_code})")
    else:
        print("Admin login failed for verification script")
except Exception as e:
    print(f"Group check error: {e}")

# Output result
with open("/tmp/verification_data.json", "w") as f:
    json.dump(result, f)
EOF

# Run verification script
python3 /tmp/verify_state.py

# Combine into final result
if [ -f "/tmp/verification_data.json" ]; then
    AUTH_SUCCESS=$(jq -r '.authentication_success' /tmp/verification_data.json)
    GROUP_PRESERVED=$(jq -r '.group_membership_preserved' /tmp/verification_data.json)
    USER_EXISTS=$(jq -r '.user_exists' /tmp/verification_data.json)
else
    AUTH_SUCCESS="false"
    GROUP_PRESERVED="false"
    USER_EXISTS="false"
fi

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "authentication_success": $AUTH_SUCCESS,
    "group_membership_preserved": $GROUP_PRESERVED,
    "user_exists": $USER_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move with permission safety
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="