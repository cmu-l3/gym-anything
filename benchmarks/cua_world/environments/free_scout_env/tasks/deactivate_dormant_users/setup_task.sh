#!/bin/bash
set -e
echo "=== Setting up deactivate_dormant_users task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Helper to Create User =====
# FreeScout uses bcrypt. This hash is for 'Password123!'
PASSWORD_HASH='\$2y\$10\$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'

create_user_with_login() {
    local first="$1"
    local last="$2"
    local email="$3"
    local days_ago="$4" # "NULL" or number of days
    
    local login_val="NULL"
    if [ "$days_ago" != "NULL" ]; then
        login_val="DATE_SUB(NOW(), INTERVAL $days_ago DAY)"
    fi

    # Check if exists, if not create
    local exists
    exists=$(fs_query "SELECT id FROM users WHERE email='$email'")
    
    if [ -z "$exists" ]; then
        echo "Creating user $email..."
        # Status 1 = Active
        fs_query "INSERT INTO users (first_name, last_name, email, password, role, status, created_at, updated_at, last_login_at) VALUES ('$first', '$last', '$email', '$PASSWORD_HASH', 2, 1, NOW(), NOW(), $login_val);"
    else
        echo "Updating user $email..."
        fs_query "UPDATE users SET status=1, last_login_at=$login_val WHERE email='$email';"
    fi
}

# ===== Seed Users with Specific Timestamps =====
echo "Seeding user data..."

# 1. Active User (Recent) - 5 days ago (Should KEEP ACTIVE)
create_user_with_login "Alice" "Active" "active.recent@helpdesk.local" "5"

# 2. Active User (Borderline) - 80 days ago (Should KEEP ACTIVE - <90 days)
create_user_with_login "Bob" "Borderline" "active.borderline@helpdesk.local" "80"

# 3. Dormant User (Old) - 180 days ago (Should DEACTIVATE - >90 days)
create_user_with_login "Charlie" "Dormant" "dormant.old@helpdesk.local" "180"

# 4. Dormant User (Never) - NULL (Should DEACTIVATE)
create_user_with_login "Dana" "Ghost" "dormant.never@helpdesk.local" "NULL"

# Ensure Admin is active and logged in recently
fs_query "UPDATE users SET status=1, last_login_at=NOW() WHERE email='admin@helpdesk.local';"

# Record initial counts and state
get_user_count > /tmp/initial_user_count.txt
echo "Initial user count: $(cat /tmp/initial_user_count.txt)"

# Clear cache to ensure DB changes reflect in UI
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ===== Application Setup =====
# Ensure Firefox is open
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/users' > /tmp/firefox.log 2>&1 &"
    sleep 10
fi

# Wait for window
wait_for_window "firefox|mozilla|freescout" 30

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Ensure we are at the Users page (login if needed)
ensure_logged_in
navigate_to_url "http://localhost:8080/users"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="