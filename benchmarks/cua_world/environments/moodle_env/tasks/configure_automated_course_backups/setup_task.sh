#!/bin/bash
# Setup script for Configure Automated Course Backups task

echo "=== Setting up Backup Configuration Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Create the backup directory with proper permissions
BACKUP_DIR="/var/moodledata/backups_auto"
echo "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
chown www-data:www-data "$BACKUP_DIR"
chmod 777 "$BACKUP_DIR"

# 2. Reset automated backup settings to defaults (disabled)
echo "Resetting backup configuration in database..."
moodle_query "DELETE FROM mdl_config_plugins WHERE plugin='backup' AND name LIKE 'backup_auto_%'"

# 3. Record task start time
date +%s > /tmp/task_start_timestamp

# 4. Launch Firefox
echo "Starting Firefox..."
MOODLE_URL="http://localhost/admin/search.php" # Go to admin search to give a hint or just root
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 5. Wait for window and focus
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="