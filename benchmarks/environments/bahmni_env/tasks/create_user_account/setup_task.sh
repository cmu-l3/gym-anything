#!/bin/bash
set -e
echo "=== Setting up Create User Account Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial user count via SQL for robustness
echo "Recording initial user count..."
INITIAL_COUNT=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "SELECT COUNT(*) FROM users WHERE retired = 0;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_user_count.txt
log "Initial user count: $INITIAL_COUNT"

# CLEANUP: Ensure target user does not exist
# We use SQL to hard delete if exists to ensure a clean state for the agent
TARGET_USERNAME="anita.sharma"
log "Cleaning up any existing user '$TARGET_USERNAME'..."

# Get user_id if exists
USER_ID=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "SELECT user_id FROM users WHERE username = '$TARGET_USERNAME';" 2>/dev/null || echo "")

if [ -n "$USER_ID" ]; then
    log "User $TARGET_USERNAME exists (ID: $USER_ID). Deleting..."
    
    # Get person_id
    PERSON_ID=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "SELECT person_id FROM users WHERE user_id = $USER_ID;" 2>/dev/null || echo "")
    
    # Delete user roles
    docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e "DELETE FROM user_role WHERE user_id = $USER_ID;" 2>/dev/null
    
    # Delete user properties/settings if any (tables like user_property)
    docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e "DELETE FROM user_property WHERE user_id = $USER_ID;" 2>/dev/null || true
    
    # Delete the user
    docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e "DELETE FROM users WHERE user_id = $USER_ID;" 2>/dev/null
    
    # Clean up person records if we found a person_id
    if [ -n "$PERSON_ID" ]; then
        log "Cleaning up person ID: $PERSON_ID"
        docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e "DELETE FROM person_name WHERE person_id = $PERSON_ID;" 2>/dev/null || true
        docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e "DELETE FROM person_address WHERE person_id = $PERSON_ID;" 2>/dev/null || true
        docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e "DELETE FROM person_attribute WHERE person_id = $PERSON_ID;" 2>/dev/null || true
        docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e "DELETE FROM person WHERE person_id = $PERSON_ID;" 2>/dev/null || true
    fi
    log "Cleanup complete."
else
    log "User $TARGET_USERNAME not found. Clean state confirmed."
fi

# Ensure Bahmni is reachable before starting
if ! wait_for_bahmni 300; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Start browser at login page
if ! start_browser "$BAHMNI_LOGIN_URL" 3; then
  echo "ERROR: Failed to start browser"
  exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="