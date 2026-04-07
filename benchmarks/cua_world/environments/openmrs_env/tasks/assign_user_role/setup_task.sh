#!/bin/bash
# Setup: assign_user_role task
# 1. Ensures user 'nurse_betty' exists.
# 2. Ensures 'nurse_betty' does NOT have the 'Organizational Doctor' role.
# 3. Logs admin in via Firefox.

set -e
echo "=== Setting up assign_user_role task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ── 1. Ensure target user exists ──────────────────────────────────────────────
TARGET_USER="nurse_betty"
TARGET_ROLE="Organizational Doctor"

echo "Checking for user: $TARGET_USER..."
USER_JSON=$(omrs_get "/user?q=$TARGET_USER&v=full")
USER_UUID=$(echo "$USER_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
if results:
    print(results[0]['uuid'])
else:
    print('')
")

if [ -z "$USER_UUID" ]; then
    echo "User $TARGET_USER not found. Creating..."
    
    # Create Person first
    PERSON_PAYLOAD='{
        "names": [{"givenName": "Betty", "familyName": "Nurse"}],
        "gender": "F",
        "birthdate": "1985-01-01"
    }'
    PERSON_RESP=$(omrs_post "/person" "$PERSON_PAYLOAD")
    PERSON_UUID=$(echo "$PERSON_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uuid', ''))")
    
    if [ -z "$PERSON_UUID" ]; then
        echo "ERROR: Failed to create person for user."
        exit 1
    fi

    # Create User
    USER_PAYLOAD=$(cat <<EOF
{
    "username": "$TARGET_USER",
    "password": "Password123",
    "person": "$PERSON_UUID",
    "roles": [{"role": "Nurse"}]
}
EOF
)
    USER_RESP=$(omrs_post "/user" "$USER_PAYLOAD")
    USER_UUID=$(echo "$USER_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uuid', ''))")
    
    if [ -z "$USER_UUID" ]; then
        echo "ERROR: Failed to create user."
        exit 1
    fi
    echo "Created user $TARGET_USER ($USER_UUID)"
else
    echo "Found existing user $TARGET_USER ($USER_UUID)"
fi

echo "$USER_UUID" > /tmp/target_user_uuid.txt

# ── 2. Ensure target role is MISSING ──────────────────────────────────────────
# We need to fetch the current roles and remove 'Organizational Doctor' if present.
# We will leave other roles (like 'Nurse') intact to simulate a promotion scenario.

echo "Sanitizing roles for $TARGET_USER..."
# Get current roles again to be sure
CURRENT_USER_DATA=$(omrs_get "/user/$USER_UUID?v=full")

# Construct a payload with ONLY "Nurse" role (stripping others to be safe and deterministic)
# In a real scenario we might preserve others, but forcing a known state is safer for verification.
UPDATE_PAYLOAD='{
    "roles": [{"role": "Nurse"}]
}'

omrs_post "/user/$USER_UUID" "$UPDATE_PAYLOAD" > /dev/null
echo "Reset roles for $TARGET_USER to 'Nurse' only."

# ── 3. Record Initial State ───────────────────────────────────────────────────
# Verify the reset worked
CHECK_DATA=$(omrs_get "/user/$USER_UUID?v=full")
HAS_ROLE=$(echo "$CHECK_DATA" | python3 -c "
import sys, json
data = json.load(sys.stdin)
roles = [r.get('display', '') for r in data.get('roles', [])]
print('true' if '$TARGET_ROLE' in roles else 'false')
")

if [ "$HAS_ROLE" == "true" ]; then
    echo "ERROR: Failed to remove target role during setup."
    exit 1
fi

echo "Initial state verified: $TARGET_USER does NOT have role '$TARGET_ROLE'"

# ── 4. Launch Browser ─────────────────────────────────────────────────────────
# Navigate to the System Administration page or Home
TARGET_URL="http://localhost/openmrs/spa/home"
ensure_openmrs_logged_in "$TARGET_URL"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="