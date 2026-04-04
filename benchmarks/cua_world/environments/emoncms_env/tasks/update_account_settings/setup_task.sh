#!/bin/bash
# setup_task.sh — Prepare the environment for the update_account_settings task

source /workspace/scripts/task_utils.sh

echo "=== Setting up task: update_account_settings ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------
# 1. Ensure Emoncms is running
# -----------------------------------------------------------------------
wait_for_emoncms
if [ $? -ne 0 ]; then
    echo "ERROR: Emoncms is not reachable, attempting restart..."
    cd /home/ga/emoncms && docker compose up -d
    sleep 15
    wait_for_emoncms
fi

# -----------------------------------------------------------------------
# 2. Reset account to default values (UTC, admin@emoncms.local)
#    This ensures a consistent starting state and prevents previous runs
#    from affecting verification.
# -----------------------------------------------------------------------
echo "=== Resetting account to default values ==="

# Update DB
db_query "UPDATE users SET timezone='UTC', email='admin@emoncms.local' WHERE username='admin'"

# Flush Redis cache to ensure Emoncms UI picks up the DB changes immediately
echo "Flushing Redis cache..."
docker exec emoncms-redis redis-cli FLUSHALL > /dev/null 2>&1 || true

# -----------------------------------------------------------------------
# 3. Record initial state for anti-gaming verification
# -----------------------------------------------------------------------
INITIAL_TIMEZONE=$(db_query "SELECT timezone FROM users WHERE username='admin'" | head -1)
INITIAL_EMAIL=$(db_query "SELECT email FROM users WHERE username='admin'" | head -1)

echo "Initial timezone set to: '${INITIAL_TIMEZONE}'"
echo "Initial email set to: '${INITIAL_EMAIL}'"

# Save initial state to file
cat > /tmp/task_initial_state.json << EOF
{
  "initial_timezone": "${INITIAL_TIMEZONE}",
  "initial_email": "${INITIAL_EMAIL}",
  "timestamp": "$(date -Iseconds)"
}
EOF

# -----------------------------------------------------------------------
# 4. Launch Firefox to the account page
# -----------------------------------------------------------------------
echo "=== Launching Firefox to My Account page ==="
launch_firefox_to "http://localhost/user/view" 8

# Take a screenshot of the initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="