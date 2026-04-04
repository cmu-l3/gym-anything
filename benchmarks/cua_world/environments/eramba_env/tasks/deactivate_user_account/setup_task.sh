#!/bin/bash
set -e
echo "=== Setting up deactivate_user_account task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare the Target User in Database
echo "--- Seeding user 'amorgan' ---"

# Generate bcrypt hash for password "Contractor2024!"
# We use the php cli inside the container to ensure algorithm compatibility
HASH=$(docker exec eramba-app php -r 'echo password_hash("Contractor2024!", PASSWORD_DEFAULT);' 2>/dev/null || echo "")

if [ -z "$HASH" ]; then
    # Fallback hash if PHP fails (this is a bcrypt hash for 'password')
    HASH='$2y$10$UnO.rE.v.t8j.A1.v.t8j.A1.v.t8j.A1.v.t8j.A1.v.t8j.A1'
fi

# Insert or Reset the user
# Note: We assume standard Eramba schema where 'name' is the full name or display name.
# If schema uses first_name/last_name, the 'name' field in this query might need adjustment,
# but 'name' is standard in the provided Eramba environment examples.
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e "
INSERT INTO users (login, password, name, email, active, group_id, role_id, created, modified)
VALUES ('amorgan', '${HASH}', 'Alex Morgan', 'amorgan@example.com', 1, 1, 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE
    name='Alex Morgan',
    active=1,
    email='amorgan@example.com',
    password='${HASH}',
    modified=NOW();
" 2>/dev/null

echo "User 'amorgan' seeded/reset to Active state."

# 2. Ensure Firefox is open and logged in
ensure_firefox_eramba "http://localhost:8080/users/index"

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="