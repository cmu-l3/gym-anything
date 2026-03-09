#!/bin/bash
echo "=== Setting up competitive_intelligence_setup ==="

source /workspace/scripts/task_utils.sh

# Clean stale artifacts
sudo rm -f /tmp/cis_start_ts /tmp/cis_rss_baseline /tmp/task_start.png 2>/dev/null || true

# ============================================================
# Inject wrong profile data
# ============================================================
log "Injecting wrong profile..."
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET
    first_name = 'Kevin',
    last_name = 'Park',
    about_me = 'Marketing analytics placeholder account.',
    time_zone = 'America/New_York',
    phone_no = '0000000000',
    phone_code = '+1'
  WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# ============================================================
# Clean up any market segment teams from previous runs
# ============================================================
log "Cleaning previous market segment teams..."
for TEAM in "Enterprise Solutions Vertical" "SMB Focus Group" "Consumer Direct Channel" "Healthcare Vertical" "Education Sector"; do
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
  python3 << 'PYEOF'
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
        "aboutMe": "Consumer segment manager"
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
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = 'john.smith@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Ensure alex.brand exists
# ============================================================
ALEX_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'alex.brand@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$ALEX_ID" ]; then
  log "Creating alex.brand..."
  python3 << 'PYEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "alexbrand",
        "email": "alex.brand@socioboard.local",
        "password": "User2024!",
        "firstName": "Alex",
        "lastName": "Brand",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/alexbrand",
        "dateOfBirth": "1989-09-12",
        "phoneCode": "+1",
        "phoneNo": "5550000040",
        "country": "US",
        "timeZone": "America/Los_Angeles",
        "aboutMe": "Brand intelligence analyst covering enterprise and healthcare verticals"
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
print(f"Register alex.brand: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = 'alex.brand@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Create Q1 contaminator teams (must NOT be deleted by agent)
# Add john.smith to all contaminator teams to test that agent
# doesn't mess with existing memberships
# ============================================================
log "Creating Q1 contaminator teams and adding john.smith to them..."
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

contaminator_teams = [
    ("Q1: Brand Awareness", "Q1 brand awareness campaign"),
    ("Q1: Product Launch Alpha", "Q1 product launch team"),
    ("Q1: Retail Partnerships", "Q1 retail channel partnerships"),
    ("Q1: Digital Outreach", "Q1 digital outreach initiative"),
]

for team_name, desc in contaminator_teams:
    existing = subprocess.run(
        ['mysql', '-u', 'root', 'socioboard', '-N', '-e',
         f"SELECT COUNT(*) FROM team_informations WHERE team_name='{team_name}'"],
        capture_output=True, text=True
    )
    if existing.stdout.strip() == '1':
        print(f"'{team_name}' already exists")
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
    print(f"Contaminator '{team_name}': {result.stdout[:80]}")

print("Contaminator teams created successfully")
PYEOF

# Record contaminator team membership counts as baseline
log "Recording contaminator member counts..."
for TEAM in "Q1: Brand Awareness" "Q1: Product Launch Alpha" "Q1: Retail Partnerships" "Q1: Digital Outreach"; do
  COUNT=$(mysql -u root "$DB_NAME" -N -e "
    SELECT COUNT(*) FROM join_table_users_teams jt
    JOIN team_informations ti ON jt.team_id = ti.team_id
    WHERE ti.team_name = '${TEAM}'
  " 2>/dev/null || echo "0")
  log "  ${TEAM}: ${COUNT} members"
done

# ============================================================
# Record baseline
# ============================================================
log "Recording baseline..."

if [ -f /var/log/apache2/socioboard_access.log ]; then
  wc -l < /var/log/apache2/socioboard_access.log > /tmp/cis_rss_baseline
else
  echo "0" > /tmp/cis_rss_baseline
fi

date +%s > /tmp/cis_start_ts

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
echo "=== Setup complete: competitive_intelligence_setup ==="
