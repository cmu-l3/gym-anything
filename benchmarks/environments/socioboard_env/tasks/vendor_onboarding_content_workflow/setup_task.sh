#!/bin/bash
echo "=== Setting up vendor_onboarding_content_workflow ==="

source /workspace/scripts/task_utils.sh

sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png /tmp/rss_log_baseline 2>/dev/null || true

# ============================================================
# Corrupt admin profile (error injection)
# ============================================================
log "Injecting wrong profile data..."
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET
    first_name = 'Alex',
    last_name = 'Petrov',
    about_me = 'Social media coordinator. Part-time contractor.',
    time_zone = 'Asia/Tokyo',
    phone_no = '0000000000',
    phone_code = '+81'
  WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# ============================================================
# Clean up target teams from previous runs
# ============================================================
log "Cleaning previous task teams..."
for TEAM in "Q2 Product Launches" "Customer Engagement Pod" "Seasonal Promotions Q2-2026"; do
  mysql -u root "$DB_NAME" -e "
    DELETE FROM join_table_users_teams WHERE team_id IN
      (SELECT team_id FROM team_informations WHERE team_name = '${TEAM}')
  " 2>/dev/null || true
  mysql -u root "$DB_NAME" -e "
    DELETE FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || true
done

# ============================================================
# Create contaminator teams (similar but wrong names)
# ============================================================
log "Creating contaminator teams..."
python3 << 'PYEOF'
import subprocess, json, tempfile, os, sys

admin_email = "admin@socioboard.local"
admin_pass = "Admin2024!"

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
    token = json.loads(result.stdout).get('accessToken', '')
except Exception:
    token = ''

if not token:
    print("Login failed", file=sys.stderr)
    sys.exit(1)

for team_name, desc in [
    ("Product Launches", "Q1 product launch coordination"),
    ("Customer Support", "Support ticket triage team")
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
# Ensure john.smith and emily.chen exist
# ============================================================
log "Ensuring users exist..."
python3 << 'PYEOF'
import subprocess, json, tempfile, os

users = [
    {
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
        "aboutMe": "Marketing analyst"
    },
    {
        "userName": "emilychen",
        "email": "emily.chen@socioboard.local",
        "password": "User2024!",
        "firstName": "Emily",
        "lastName": "Chen",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/emilychen",
        "dateOfBirth": "1992-03-22",
        "phoneCode": "+1",
        "phoneNo": "5550000003",
        "country": "US",
        "timeZone": "America/New_York",
        "aboutMe": "Content strategist"
    }
]

for user_data in users:
    body = {"user": user_data}
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(body, f)
        tmpfile = f.name

    result = subprocess.run(
        ['curl', '-s', '-X', 'PUT', '-H', 'Content-Type: application/json',
         '-d', '@' + tmpfile, 'http://127.0.0.1:3000/v1/register'],
        capture_output=True, text=True, timeout=30
    )
    os.unlink(tmpfile)
    print(f"Register {user_data['email']}: {result.stdout[:150]}")
PYEOF

# Activate all users and set premium plan
mysql -u root "$DB_NAME" -e "
  UPDATE user_activations SET activation_status = 1, user_plan = 2
" 2>/dev/null || true

# ============================================================
# Record baseline
# ============================================================
log "Recording baseline..."

CONTAM1_MEMBERS=$(mysql -u root "$DB_NAME" -N -e "
  SELECT COUNT(*) FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  WHERE ti.team_name = 'Product Launches'
" 2>/dev/null || echo "0")
echo "$CONTAM1_MEMBERS" > /tmp/contam1_baseline

CONTAM2_MEMBERS=$(mysql -u root "$DB_NAME" -N -e "
  SELECT COUNT(*) FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  WHERE ti.team_name = 'Customer Support'
" 2>/dev/null || echo "0")
echo "$CONTAM2_MEMBERS" > /tmp/contam2_baseline

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
echo "=== Setup complete: vendor_onboarding_content_workflow ==="
