#!/bin/bash
echo "=== Setting up resolve_credential_conflict task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Access Commander to be ready
wait_for_ac_demo

# Authenticate via REST API
ac_login

# 1. Idempotency: Clean up "Samuel Jenkins" if he exists from a previous aborted run
EXISTING_SAMUEL=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Samuel" and .lastName=="Jenkins") | .id' 2>/dev/null)
for uid in $EXISTING_SAMUEL; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1
    echo "Deleted prior Samuel Jenkins (id=$uid)"
done

# 2. Ensure "Derek Caldwell" is seeded and possesses the conflict card (0013988412)
# (seed_ac_data.py handles initial creation, but this ensures a clean starting state)
EXISTING_DEREK=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Derek" and .lastName=="Caldwell") | .id' 2>/dev/null)
if [ -n "$EXISTING_DEREK" ]; then
    # Force set the credential to Derek
    ac_api PUT "/users/$EXISTING_DEREK/credentials" '{"cards":["0013988412"]}' > /dev/null 2>&1
    echo "Ensured Derek Caldwell has card 0013988412 assigned"
else
    echo "WARNING: Derek Caldwell not found. Seed data might be missing."
fi

# Launch Firefox pointing to the main dashboard
launch_firefox_to "${AC_URL}/" 8

# Capture initial state evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="