#!/bin/bash
# Setup script for manage_customer_accounts task
echo "=== Setting up manage_customer_accounts ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils missing or incomplete
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Ensure services are running
ensure_services_running 120

# 1. Reset/Ensure initial users exist
echo "Resetting user data..."

# Reset mikewilson (ensure active)
EXISTING_MIKE=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name='mikewilson'")
if [ -n "$EXISTING_MIKE" ]; then
    drupal_db_query "UPDATE users_field_data SET status=1 WHERE name='mikewilson'"
else
    cd /var/www/html/drupal && vendor/bin/drush user:create mikewilson --mail="mike.wilson@example.com" --password="Customer123!"
fi

# Reset janesmith (ensure original email)
EXISTING_JANE=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name='janesmith'")
if [ -n "$EXISTING_JANE" ]; then
    drupal_db_query "UPDATE users_field_data SET mail='jane.smith@example.com' WHERE name='janesmith'"
else
    cd /var/www/html/drupal && vendor/bin/drush user:create janesmith --mail="jane.smith@example.com" --password="Customer123!"
fi

# Ensure sarahjohnson does NOT exist (clean slate)
EXISTING_SARAH=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name='sarahjohnson'")
if [ -n "$EXISTING_SARAH" ]; then
    echo "Removing existing sarahjohnson account..."
    # Delete profiles first
    PROFILE_IDS=$(drupal_db_query "SELECT profile_id FROM profile WHERE uid=$EXISTING_SARAH")
    if [ -n "$PROFILE_IDS" ]; then
        drupal_db_query "DELETE FROM profile__address WHERE entity_id IN ($PROFILE_IDS)"
        drupal_db_query "DELETE FROM profile WHERE uid=$EXISTING_SARAH"
    fi
    cd /var/www/html/drupal && vendor/bin/drush user:cancel --delete-content "$EXISTING_SARAH" -y
fi

# Record timestamps and initial counts
date +%s > /tmp/task_start_timestamp
drupal_db_query "SELECT COUNT(*) FROM users_field_data" > /tmp/initial_user_count

# Navigate to People page
echo "Navigating to People administration..."
navigate_firefox_to "http://localhost/admin/people"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup Complete ==="