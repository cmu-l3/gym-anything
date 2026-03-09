#!/bin/bash
echo "=== Setting up modify_user_permissions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Verify CouchDB and HospitalRun are running
echo "Checking system availability..."
wait_for_db_ready

# 2. Seed the target user 'jmiller' in the _users database
# We use the CouchDB admin credentials defined in task_utils.sh (HR_COUCH_URL)
# User: jmiller, Role: Doctor (only)
echo "Seeding user jmiller..."

TARGET_DOC_ID="org.couchdb.user:jmiller"
USERS_DB="_users"

# Check if user exists to get rev for deletion/update, or just overwrite
# We'll just try to PUT. If it conflicts, we get the rev and DELETE first.
EXISTING_REV=$(curl -s "${HR_COUCH_URL}/${USERS_DB}/${TARGET_DOC_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")

if [ -n "$EXISTING_REV" ]; then
    echo "Removing existing jmiller user..."
    curl -s -X DELETE "${HR_COUCH_URL}/${USERS_DB}/${TARGET_DOC_ID}?rev=${EXISTING_REV}" > /dev/null
fi

# Create the user with explicit fields required by HospitalRun/CouchDB
# HospitalRun users need: name, password, roles, type='user', userPrefix
# metadata is often used for display names
USER_JSON=$(cat <<EOF
{
  "name": "jmiller",
  "password": "password123",
  "roles": ["Doctor", "user"],
  "type": "user",
  "userPrefix": "p2",
  "metadata": {
      "firstName": "James",
      "lastName": "Miller",
      "email": "jmiller@hospital.org"
  }
}
EOF
)

# Insert the user
curl -s -X PUT "${HR_COUCH_URL}/${USERS_DB}/${TARGET_DOC_ID}" \
    -H "Content-Type: application/json" \
    -d "$USER_JSON" > /dev/null

echo "User jmiller seeded with 'Doctor' role."

# 3. Record the initial revision of the user doc (to verify it changes)
INITIAL_REV=$(curl -s "${HR_COUCH_URL}/${USERS_DB}/${TARGET_DOC_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$INITIAL_REV" > /tmp/initial_user_rev.txt

# 4. Ensure Firefox is open and logged in as Admin
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 5. Navigate to the Dashboard (neutral starting state)
navigate_firefox_to "http://localhost:3000"

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="