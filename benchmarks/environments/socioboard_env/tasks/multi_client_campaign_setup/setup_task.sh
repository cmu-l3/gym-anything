#!/bin/bash
echo "=== Setting up multi_client_campaign_setup ==="

source /workspace/scripts/task_utils.sh

# Clean up stale files from previous runs
sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png /tmp/rss_log_baseline 2>/dev/null || true

# ============================================================
# Corrupt admin profile (error injection)
# ============================================================
log "Injecting wrong profile data..."
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET
    first_name = 'Jordan',
    last_name = 'Blake',
    about_me = 'Former intern. Temporary account.',
    time_zone = 'America/Los_Angeles',
    phone_no = '0000000000',
    phone_code = '+1'
  WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# ============================================================
# Clean up any GlobalTech teams from previous runs
# ============================================================
log "Cleaning up previous GlobalTech teams..."
for TEAM in "GlobalTech - Paid Social" "GlobalTech - Organic Content" "GlobalTech - Influencer Outreach" "GlobalTech - Performance Analytics"; do
  mysql -u root "$DB_NAME" -e "
    DELETE FROM join_table_users_teams WHERE team_id IN
      (SELECT team_id FROM team_informations WHERE team_name = '${TEAM}')
  " 2>/dev/null || true
  mysql -u root "$DB_NAME" -e "
    DELETE FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || true
done

# ============================================================
# Create contaminator teams (should not be touched by agent)
# ============================================================
log "Creating contaminator teams..."
python3 << 'PYEOF'
import subprocess, json, tempfile, os, sys

admin_email = "admin@socioboard.local"
admin_pass = "Admin2024!"

# Login
login_body = {"user": admin_email, "password": admin_pass}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(login_body, f)
    login_tmp = f.name

result = subprocess.run(
    ['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json',
     '-d', '@' + login_tmp, 'http://127.0.0.1:3000/v1/login'],
    capture_output=True, text=True, timeout=30
)
os.unlink(login_tmp)

try:
    login_data = json.loads(result.stdout)
    token = login_data.get('accessToken', '')
except Exception as e:
    print(f"Login failed: {e}", file=sys.stderr)
    sys.exit(1)

if not token:
    print(f"No token: {result.stdout[:200]}", file=sys.stderr)
    sys.exit(1)

# Create contaminator teams
for team_name, desc in [
    ("Old Campaign Draft", "Leftover from Q3 2025 campaign"),
    ("Test Team DELETE ME", "Testing purposes only")
]:
    team_body = {"TeamInfo": {"name": team_name, "description": desc}}
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(team_body, f)
        team_tmp = f.name

    result = subprocess.run(
        ['curl', '-s', '-X', 'POST',
         '-H', 'Content-Type: application/json',
         '-H', 'x-access-token: ' + token,
         '-d', '@' + team_tmp,
         'http://127.0.0.1:3000/v1/team/create'],
        capture_output=True, text=True, timeout=30
    )
    os.unlink(team_tmp)
    print(f"Contaminator '{team_name}': {result.stdout[:100]}")
PYEOF

# ============================================================
# Record baseline state
# ============================================================
log "Recording baseline state..."

# Record contaminator team member counts
CONTAM1_MEMBERS=$(mysql -u root "$DB_NAME" -N -e "
  SELECT COUNT(*) FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  WHERE ti.team_name = 'Old Campaign Draft'
" 2>/dev/null || echo "0")
echo "$CONTAM1_MEMBERS" > /tmp/contam1_baseline

CONTAM2_MEMBERS=$(mysql -u root "$DB_NAME" -N -e "
  SELECT COUNT(*) FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  WHERE ti.team_name = 'Test Team DELETE ME'
" 2>/dev/null || echo "0")
echo "$CONTAM2_MEMBERS" > /tmp/contam2_baseline

# Record Apache log baseline for RSS check
if [ -f /var/log/apache2/socioboard_access.log ]; then
  wc -l < /var/log/apache2/socioboard_access.log > /tmp/rss_log_baseline
else
  echo "0" > /tmp/rss_log_baseline
fi

# Record timestamp
date +%s > /tmp/task_start_timestamp

# ============================================================
# Ensure john.smith exists
# ============================================================
JOHN_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'john.smith@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$JOHN_ID" ]; then
  log "Creating john.smith user..."
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
        "aboutMe": "Team member"
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
# Navigate browser to login page
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
echo "=== Setup complete: multi_client_campaign_setup ==="
