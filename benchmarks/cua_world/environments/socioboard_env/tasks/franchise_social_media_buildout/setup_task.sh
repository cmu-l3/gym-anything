#!/bin/bash
echo "=== Setting up franchise_social_media_buildout ==="

source /workspace/scripts/task_utils.sh

sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png /tmp/rss_log_baseline 2>/dev/null || true

# ============================================================
# Corrupt admin profile
# ============================================================
log "Injecting placeholder profile data..."
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET
    first_name = 'System',
    last_name = 'Administrator',
    about_me = 'IT department setup account. Please update.',
    time_zone = 'UTC',
    phone_no = '0000000000',
    phone_code = '+1'
  WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# ============================================================
# Clean up Crestview teams from previous runs
# ============================================================
log "Cleaning previous Crestview teams..."
for TEAM in "Crestview - Manhattan Office" "Crestview - Brooklyn Office" "Crestview - Boston Office" "Crestview - Philadelphia Office" "Crestview - National Brand"; do
  mysql -u root "$DB_NAME" -e "
    DELETE FROM join_table_users_teams WHERE team_id IN
      (SELECT team_id FROM team_informations WHERE team_name = '${TEAM}')
  " 2>/dev/null || true
  mysql -u root "$DB_NAME" -e "
    DELETE FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || true
done

# ============================================================
# Ensure john.smith exists
# ============================================================
JOHN_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'john.smith@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$JOHN_ID" ]; then
  log "Creating john.smith..."
  python3 << 'PYPEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "johnsmith",
        "email": "john.smith@socioboard.local",
        "password": "User2024!",
        "firstName": "John",
        "lastName": "Smith",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/johnsmith",
        "dateOfBirth": "1985-06-15",
        "phoneCode": "+1",
        "phoneNo": "5550000002",
        "country": "US",
        "timeZone": "America/New_York",
        "aboutMe": "Regional marketing coordinator"
    }
}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(body, f)
    tmpfile = f.name

result = subprocess.run(
    ['curl', '-s', '-X', 'PUT', '-H', 'Content-Type: application/json',
     '-d', '@' + tmpfile, 'http://127.0.0.1:3000/v1/register'],
    capture_output=True, text=True, timeout=30
)
os.unlink(tmpfile)
print(f"Register john.smith: {result.stdout[:200]}")
PYPEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = 'john.smith@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Record baseline
# ============================================================
log "Recording baseline..."

if [ -f /var/log/apache2/socioboard_access.log ]; then
  wc -l < /var/log/apache2/socioboard_access.log > /tmp/rss_log_baseline
else
  echo "0" > /tmp/rss_log_baseline
fi

date +%s > /tmp/task_start_timestamp

# ============================================================
# Navigate to login
# ============================================================
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable"
  exit 1
fi

log "Clearing browser session..."
open_socioboard_page "http://localhost/logout"
sleep 2
navigate_to "http://localhost/login"
sleep 3

take_screenshot /tmp/task_start.png
log "Task start screenshot saved"
echo "=== Setup complete: franchise_social_media_buildout ==="
