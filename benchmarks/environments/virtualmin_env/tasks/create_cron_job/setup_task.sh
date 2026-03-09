#!/bin/bash
set -e
echo "=== Setting up create_cron_job task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Determine target user (usually 'acmecorp' for acmecorp.test)
TARGET_USER="acmecorp"
# Ensure user exists (created by install/setup scripts), if not fallback to root for setup safety
if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "WARNING: User $TARGET_USER not found, checking virtualmin..."
    TARGET_USER=$(virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null | grep "Username:" | awk '{print $2}')
fi
echo "$TARGET_USER" > /tmp/target_user.txt

# 3. Create the dummy script
SCRIPT_DIR="/home/${TARGET_USER}/bin"
SCRIPT_PATH="${SCRIPT_DIR}/db_maintenance.sh"

mkdir -p "$SCRIPT_DIR"
cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash
# Database Maintenance Script
# Optimizes tables and clears cache
echo "Running database maintenance..."
sleep 1
echo "Done."
EOF

chmod +x "$SCRIPT_PATH"
chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}/bin" 2>/dev/null || true

echo "Created script at $SCRIPT_PATH"

# 4. Clean up any existing cron jobs for this script (Idempotency)
# Remove lines containing db_maintenance.sh from the user's crontab
if crontab -u "$TARGET_USER" -l 2>/dev/null | grep -q "db_maintenance.sh"; then
    echo "Removing existing cron job..."
    crontab -u "$TARGET_USER" -l 2>/dev/null | grep -v "db_maintenance.sh" | crontab -u "$TARGET_USER" -
fi

# 5. Record initial state (should be empty of this job)
crontab -u "$TARGET_USER" -l 2>/dev/null > /tmp/initial_crontab.txt || true
md5sum /var/spool/cron/crontabs/$TARGET_USER 2>/dev/null > /tmp/initial_spool_hash.txt || echo "none" > /tmp/initial_spool_hash.txt

# 6. Ensure Virtualmin is ready in Firefox
ensure_virtualmin_ready
sleep 2

# Navigate to System > Scheduled Cron Jobs to give a helpful starting point
# Or just leave at dashboard. The task description says "Navigate to...", so starting at dashboard is fine.
# But for reliability, let's go to the main index.
navigate_to "https://localhost:10000/?cat=system"
sleep 3

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="