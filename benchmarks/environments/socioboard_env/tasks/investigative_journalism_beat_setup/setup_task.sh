#!/bin/bash
echo "=== Setting up investigative_journalism_beat_setup ==="

source /workspace/scripts/task_utils.sh

# Clean up stale run artifacts
sudo rm -f /tmp/ijbs_start_ts /tmp/ijbs_rss_baseline /tmp/task_start.png 2>/dev/null || true

# ============================================================
# Inject placeholder profile (admin must NOT need to update
# their profile in this task — we still reset it to a neutral
# value so it doesn't contaminate other task checks)
# ============================================================
log "Resetting admin profile to neutral state..."
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET
    first_name = 'Admin',
    last_name = 'User',
    about_me = 'System administrator account',
    time_zone = 'UTC',
    phone_no = '0000000000',
    phone_code = '+1'
  WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# ============================================================
# Clean up any beat teams from previous runs
# ============================================================
log "Cleaning previous beat teams..."
for TEAM in "Politics & Government" "Technology & Innovation" "Climate & Environment" "Finance & Markets" "Public Health"; do
  mysql -u root "$DB_NAME" -e "
    DELETE FROM join_table_users_teams WHERE team_id IN
      (SELECT team_id FROM team_informations WHERE team_name = '${TEAM}')
  " 2>/dev/null || true
  mysql -u root "$DB_NAME" -e "
    DELETE FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || true
done

# ============================================================
# Ensure emily.chen exists
# ============================================================
EMILY_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'emily.chen@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$EMILY_ID" ]; then
  log "Creating emily.chen..."
  python3 << 'PYEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "emilychen",
        "email": "emily.chen@socioboard.local",
        "password": "User2024!",
        "firstName": "Emily",
        "lastName": "Chen",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/emilychen",
        "dateOfBirth": "1990-03-22",
        "phoneCode": "+1",
        "phoneNo": "5550000010",
        "country": "US",
        "timeZone": "America/New_York",
        "aboutMe": "Politics and finance reporter at The Meridian Tribune"
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
print(f"Register emily.chen: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = 'emily.chen@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Ensure michael.okafor exists
# ============================================================
MICHAEL_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'michael.okafor@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$MICHAEL_ID" ]; then
  log "Creating michael.okafor..."
  python3 << 'PYEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "michaelokafor",
        "email": "michael.okafor@socioboard.local",
        "password": "User2024!",
        "firstName": "Michael",
        "lastName": "Okafor",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/michaelokafor",
        "dateOfBirth": "1988-07-14",
        "phoneCode": "+1",
        "phoneNo": "5550000011",
        "country": "US",
        "timeZone": "America/Chicago",
        "aboutMe": "Technology and science reporter at The Meridian Tribune"
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
print(f"Register michael.okafor: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = 'michael.okafor@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Create contaminator teams (legacy teams from CMS migration)
# ============================================================
log "Creating contaminator teams..."
python3 << 'PYEOF'
import subprocess, json, tempfile, os, sys

login_body = {"user": "admin@socioboard.local", "password": "Admin2024!"}
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
    token = json.loads(result.stdout).get('accessToken', '')
except Exception:
    token = ''

if not token:
    print(f"No token: {result.stdout[:200]}", file=sys.stderr)
    sys.exit(0)

for team_name, desc in [
    ("Morning Briefing Archive", "Legacy CMS team - do not delete"),
    ("Sports Desk Legacy", "Previous sports coverage team - archived")
]:
    existing = subprocess.run(
        ['mysql', '-u', 'root', 'socioboard', '-N', '-e',
         f"SELECT COUNT(*) FROM team_informations WHERE team_name='{team_name}'"],
        capture_output=True, text=True
    )
    if existing.stdout.strip() == '1':
        print(f"Contaminator '{team_name}' already exists, skipping")
        continue

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

if [ -f /var/log/apache2/socioboard_access.log ]; then
  wc -l < /var/log/apache2/socioboard_access.log > /tmp/ijbs_rss_baseline
else
  echo "0" > /tmp/ijbs_rss_baseline
fi

date +%s > /tmp/ijbs_start_ts

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
echo "=== Setup complete: investigative_journalism_beat_setup ==="
