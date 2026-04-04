#!/bin/bash
echo "=== Setting up configure_log_rotation task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure acmecorp.test exists
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    # Create with default password if it doesn't exist
    virtualmin create-domain --domain acmecorp.test --pass GymAnything123! --unix --dir --web --dns --logrotate 2>/dev/null || true
fi

# 3. Reset Log Rotation to a known "bad" state (Weekly, 5 rotations, No compression)
# We use the Virtualmin CLI 'modify-logrotate' if available, or direct file edit.
# Direct file edit is safer to ensure specific starting state.
LOG_CONFIG_FILE="/etc/logrotate.d/virtualmin.conf"
LOG_PATH="/var/log/virtualmin/acmecorp.test_access_log"

# Ensure the entry exists in the config file. If not, Virtualmin usually adds it.
# We'll try to set it via CLI first to be clean.
echo "Resetting log rotation settings..."
virtualmin modify-logrotate --domain acmecorp.test --log $LOG_PATH --schedule weekly --rotate 4 --no-compress 2>/dev/null || true

# Verify/Force the state in the file
# We are looking for the block that defines the rotation for the access log
if [ -f "$LOG_CONFIG_FILE" ]; then
    # Backup for comparison
    cp "$LOG_CONFIG_FILE" /tmp/initial_logrotate.conf
fi

# 4. Prepare Firefox
ensure_virtualmin_ready

# 5. Navigate to the Log Rotation page to save time (optional, but helpful for stability)
# finding the right URL: edit_log.cgi or generic list
ACME_ID=$(get_domain_id "acmecorp.test")
# Navigating to the logs list page
navigate_to "https://localhost:10000/virtual-server/list_logs.cgi?dom=${ACME_ID}"
sleep 5

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="