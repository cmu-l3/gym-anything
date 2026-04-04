#!/bin/bash
echo "=== Setting up regional_health_education_campaign ==="

source /workspace/scripts/task_utils.sh

# Clean stale artifacts
sudo rm -f /tmp/rhec_start_ts /tmp/rhec_rss_baseline /tmp/task_start.png 2>/dev/null || true

# ============================================================
# Inject wrong profile data (agent must fix this)
# ============================================================
log "Injecting wrong profile..."
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET
    first_name = 'Tyler',
    last_name = 'Morrison',
    about_me = 'State IT department account. Configuration pending.',
    time_zone = 'America/New_York',
    phone_no = '0000000000',
    phone_code = '+1'
  WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# ============================================================
# Clean up any campaign teams from previous runs
# ============================================================
log "Cleaning previous campaign teams..."
for TEAM in "Northeast Region" "Southeast Region" "Midwest Region" "West Coast Region" "National Campaign Hub"; do
  mysql -u root "$DB_NAME" -e "
    DELETE FROM join_table_users_teams WHERE team_id IN
      (SELECT team_id FROM team_informations WHERE team_name = '${TEAM}')
  " 2>/dev/null || true
  mysql -u root "$DB_NAME" -e "
    DELETE FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || true
done

# ============================================================
# Create coordinator accounts
# ============================================================
create_user() {
  local EMAIL="$1"
  local USERNAME="$2"
  local FIRST="$3"
  local LAST="$4"
  local PHONE="$5"
  local TZ="$6"
  local BIO="$7"

  local EXISTING=$(mysql -u root "$DB_NAME" -N -e \
    "SELECT user_id FROM user_details WHERE email = '${EMAIL}' LIMIT 1" 2>/dev/null || echo "")

  if [ -n "$EXISTING" ]; then
    log "User ${EMAIL} already exists, skipping"
    return
  fi

  log "Creating ${EMAIL}..."
  python3 << PYEOF
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "${USERNAME}",
        "email": "${EMAIL}",
        "password": "User2024!",
        "firstName": "${FIRST}",
        "lastName": "${LAST}",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/${USERNAME}",
        "dateOfBirth": "1985-01-15",
        "phoneCode": "+1",
        "phoneNo": "${PHONE}",
        "country": "US",
        "timeZone": "${TZ}",
        "aboutMe": "${BIO}"
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
print(f"Register ${EMAIL}: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = '${EMAIL}')
  " 2>/dev/null || true
}

create_user "sarah.johnson@socioboard.local" "sarahjohnson" "Sarah" "Johnson" \
  "5550000020" "America/New_York" "Northeast regional health education coordinator"

create_user "david.martinez@socioboard.local" "davidmartinez" "David" "Martinez" \
  "5550000021" "America/Chicago" "Southeast and Midwest regional health coordinator"

create_user "lisa.chen@socioboard.local" "lisachen" "Lisa" "Chen" \
  "5550000022" "America/Los_Angeles" "West Coast regional health education coordinator"

# ============================================================
# Create contaminator teams (previous year archives)
# ============================================================
log "Creating archive contaminator teams..."
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
    ("2023 Flu Prevention Campaign", "Archived 2023 influenza campaign team"),
    ("2023 Opioid Awareness Drive", "Archived 2023 opioid prevention team"),
    ("2023 Mental Health Month", "Archived 2023 mental health awareness team")
]:
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
    print(f"Contaminator '{team_name}': {result.stdout[:100]}")
PYEOF

# ============================================================
# Record baseline
# ============================================================
log "Recording baseline..."

if [ -f /var/log/apache2/socioboard_access.log ]; then
  wc -l < /var/log/apache2/socioboard_access.log > /tmp/rhec_rss_baseline
else
  echo "0" > /tmp/rhec_rss_baseline
fi

date +%s > /tmp/rhec_start_ts

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
echo "=== Setup complete: regional_health_education_campaign ==="
