#!/bin/bash
set -e

echo "=== Setting up wger ==="

XAUTH="/run/user/1000/gdm/Xauthority"
WGER_DIR="/home/ga/wger"

# -----------------------------------------------------------------------
# 1. Wait for Docker daemon
# -----------------------------------------------------------------------
wait_for_docker() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker info >/dev/null 2>&1; then
            echo "Docker daemon is ready"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "ERROR: Docker daemon not ready after ${timeout}s"
    return 1
}
wait_for_docker

# -----------------------------------------------------------------------
# 2. Authenticate with Docker Hub to avoid rate limits
# -----------------------------------------------------------------------
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin \
        && echo "Docker Hub auth successful" \
        || echo "Docker Hub auth failed (continuing anyway)"
else
    echo "No .dockerhub_credentials found – proceeding without authentication"
fi

# -----------------------------------------------------------------------
# 3. Copy docker-compose files to writable home directory
# -----------------------------------------------------------------------
mkdir -p "$WGER_DIR"
cp /workspace/config/docker-compose.yml "$WGER_DIR/"
cp /workspace/config/prod.env          "$WGER_DIR/"
cp /workspace/config/nginx.conf        "$WGER_DIR/"
chown -R ga:ga "$WGER_DIR"

# -----------------------------------------------------------------------
# 4. Pull images and start services
# -----------------------------------------------------------------------
echo "=== Pulling wger Docker images (this may take several minutes) ==="
cd "$WGER_DIR"
docker compose pull

echo "=== Starting wger services ==="
docker compose up -d

# -----------------------------------------------------------------------
# 5. Wait for wger web service to be ready (up to 10 minutes)
#    The first run performs DB migrations and static collection, which
#    is slow — wger's own healthcheck uses start_period: 300s.
# -----------------------------------------------------------------------
wait_for_wger() {
    local timeout=600
    local elapsed=0
    echo "Waiting for wger web service (DB migrations + gunicorn startup)..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/v2/ 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ]; then
            echo "wger API is responding (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        sleep 15
        elapsed=$((elapsed + 15))
        echo "  Still waiting... ${elapsed}s (last HTTP: $HTTP_CODE)"
    done
    echo "ERROR: wger did not become ready within ${timeout}s"
    docker compose logs web | tail -50
    return 1
}
wait_for_wger

# Give the app a few more seconds to fully initialize
sleep 10

# -----------------------------------------------------------------------
# 5b. Run collectstatic explicitly (entrypoint only runs it when
#     DJANGO_DEBUG=False; explicit call ensures static files are always
#     available — idempotent if already run by entrypoint)
# -----------------------------------------------------------------------
echo "=== Running collectstatic to populate static files (React bundle etc.) ==="
docker exec wger-web python3 manage.py collectstatic --noinput \
    && echo "collectstatic complete" \
    || echo "Warning: collectstatic failed (non-fatal)"

# -----------------------------------------------------------------------
# 6. Sync exercises from wger.de (requires net: true)
#    This downloads ~800 exercises with categories, muscles, equipment.
# -----------------------------------------------------------------------
echo "=== Syncing exercises from wger.de ==="
docker exec wger-web python3 manage.py sync-exercises \
    && echo "Exercise sync complete" \
    || echo "Warning: exercise sync failed (non-fatal)"

# -----------------------------------------------------------------------
# 7. Generate realistic training/nutrition data for admin user
#    (Uses direct Django ORM — does not require 'faker' package)
#    Creates: 30 body weight entries, 3 workout routines, 2 nutrition
#    plans, 3 measurement categories with entries.
# -----------------------------------------------------------------------
echo "=== Generating training/nutrition seed data ==="
# Write Python seed script to a temp file and copy into container
# (avoid heredoc-pipe-to-docker-exec which fails in some execution contexts)
cat > /tmp/wger_seed_data.py << 'PYTHON_SEED_EOF'
import datetime
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.manager.models import Routine, Day
from wger.nutrition.models import NutritionPlan
from wger.measurements.models import Category, Measurement

try:
    admin = User.objects.get(username='admin')
    today = datetime.date.today()
    routine_start = today
    routine_end = today + datetime.timedelta(days=180)

    # Body weight history: 30 days, starting at 87 kg, linear decline
    for i in range(30):
        d = today - datetime.timedelta(days=30 - i)
        weight = round(87.0 - i * 0.15, 1)
        WeightEntry.objects.get_or_create(user=admin, date=d, defaults={'weight': weight})
    print('Body weight entries: 30')

    # Workout routines
    for name, desc in [
        ('Push-Pull-Legs', 'Classic PPL split for hypertrophy and strength'),
        ('5x5 Beginner', 'Foundational strength program with compound lifts'),
        ('Upper-Lower Split', 'Alternating upper and lower body training'),
    ]:
        r, created = Routine.objects.get_or_create(
            name=name, user=admin,
            defaults={'description': desc, 'start': routine_start, 'end': routine_end}
        )
        print(f'Routine {"created" if created else "exists"}: {name}')

    # Nutrition plans
    for desc in ['Maintenance Diet', 'Lean Bulk Plan']:
        p, created = NutritionPlan.objects.get_or_create(description=desc, user=admin)
        print(f'Nutrition plan {"created" if created else "exists"}: {desc}')

    # Measurement categories with entries
    cat_values = {'Body Fat': 18.0, 'Chest': 100.0, 'Waist': 82.0}
    for name, unit in [('Body Fat', '%'), ('Chest', 'cm'), ('Waist', 'cm')]:
        cat, created = Category.objects.get_or_create(name=name, unit=unit, user=admin)
        print(f'Category {"created" if created else "exists"}: {name}')
        base_val = cat_values.get(name, 10.0)
        for i in range(5):
            d = today - datetime.timedelta(days=i * 7)
            Measurement.objects.get_or_create(category=cat, date=d,
                defaults={'value': round(base_val - i * 0.2, 1)})

    print('Seed data generation complete')

except Exception as e:
    import traceback
    print(f'Warning: seed data error: {e}')
    traceback.print_exc()
PYTHON_SEED_EOF

docker cp /tmp/wger_seed_data.py wger-web:/tmp/wger_seed_data.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_seed_data.py').read())" \
    && echo "Seed script executed" \
    || echo "Warning: seed script failed"

echo "Seed data generation done"

# 7b. Ensure measurement entries exist (explicit idempotent retry in case seed script
#     had a transient failure on first run)
echo "=== Ensuring measurement seed entries exist ==="
docker exec wger-web python3 manage.py shell -c "
import datetime
from django.contrib.auth.models import User
from wger.measurements.models import Category, Measurement
admin = User.objects.get(username='admin')
today = datetime.date.today()
cat_values = {'Body Fat': 18.0, 'Chest': 100.0, 'Waist': 82.0}
units = {'Body Fat': '%', 'Chest': 'cm', 'Waist': 'cm'}
created_count = 0
for name, base_val in cat_values.items():
    cat, _ = Category.objects.get_or_create(name=name, user=admin, defaults={'unit': units[name]})
    for i in range(5):
        d = today - datetime.timedelta(days=i * 7)
        m, created = Measurement.objects.get_or_create(
            category=cat, date=d, defaults={'value': round(base_val - i * 0.2, 1)})
        if created:
            created_count += 1
print(f'Measurement entries ensured: {created_count} new, {Measurement.objects.count()} total')
" 2>/dev/null || echo "Warning: measurement ensure step failed (non-fatal)"

# -----------------------------------------------------------------------
# 8. Set up Firefox snap profile (suppress first-run dialogs)
# -----------------------------------------------------------------------
FIREFOX_PROFILE_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
mkdir -p "${FIREFOX_PROFILE_BASE}/wger.profile"

cat > "${FIREFOX_PROFILE_BASE}/profiles.ini" << 'PROFILES_EOF'
[Profile0]
Name=wger
IsRelative=1
Path=wger.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILES_EOF

cat > "${FIREFOX_PROFILE_BASE}/wger.profile/user.js" << 'USER_JS_EOF'
user_pref("browser.startup.homepage", "http://localhost/en/user/login");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("extensions.autoDisableScopes", 15);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("privacy.notices.shown", true);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.firstrunSkipsHomepage", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("signon.management.page.breach-alerts.enabled", false);
user_pref("signon.autofillForms", false);
user_pref("signon.rememberSignons", false);
USER_JS_EOF

chown -R ga:ga /home/ga/snap/ 2>/dev/null || true

# -----------------------------------------------------------------------
# 9. Kill any stale Firefox processes and launch Firefox
# -----------------------------------------------------------------------
pkill -9 -f firefox 2>/dev/null || true

# Poll until firefox processes are dead
for i in $(seq 1 10); do
    pgrep -f firefox >/dev/null 2>&1 || break
    sleep 1
done

# Remove stale lock files
rm -f "${FIREFOX_PROFILE_BASE}/wger.profile/.parentlock" \
      "${FIREFOX_PROFILE_BASE}/wger.profile/lock" 2>/dev/null || true

sleep 2

# Launch Firefox as ga user
su - ga -c "
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/wger.profile/.parentlock \
          /home/ga/snap/firefox/common/.mozilla/firefox/wger.profile/lock 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=${XAUTH} \
    setsid firefox --new-instance \
        -profile /home/ga/snap/firefox/common/.mozilla/firefox/wger.profile \
        'http://localhost/en/user/login' &
"

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -qi "firefox"; then
        echo "Firefox window appeared"
        break
    fi
    sleep 2
done
sleep 3

# Maximize Firefox window
DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: \
    -b add,maximized_vert,maximized_horz 2>/dev/null || true

# -----------------------------------------------------------------------
# 10. Log in to wger as admin in Firefox (username field has autofocus)
# -----------------------------------------------------------------------
echo "Logging in to wger as admin..."
sleep 5

# Wait for the login page to fully load (poll for title)
for i in $(seq 1 20); do
    PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY="${XAUTH}" xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "$PAGE_TITLE" | grep -qi "wger\|login\|firefox"; then
        echo "Firefox window ready: $PAGE_TITLE"
        break
    fi
    sleep 1
done
sleep 3

# Dismiss any first-run wizard popups with Escape
DISPLAY=:1 XAUTHORITY="${XAUTH}" xdotool key Escape 2>/dev/null || true
sleep 1

# Use Ctrl+L to focus address bar and navigate to login
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key ctrl+l"
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'http://localhost/en/user/login'"
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return"
sleep 4

# Dismiss any dialogs (e.g., Firefox sidebar popup)
DISPLAY=:1 XAUTHORITY="${XAUTH}" xdotool key Escape 2>/dev/null || true
sleep 1

# Click username field (autofocus should work, but use Tab as fallback)
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Tab"
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key shift+Tab"
sleep 0.3

# Type username
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'admin'"
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Tab"
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'adminadmin'"
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return"
sleep 5

# Take a screenshot to verify the setup
DISPLAY=:1 XAUTHORITY="${XAUTH}" xwd -root -silent -out /tmp/wger_setup.xwd 2>/dev/null \
    && convert /tmp/wger_setup.xwd /tmp/wger_setup_screenshot.png 2>/dev/null \
    && rm -f /tmp/wger_setup.xwd || true

echo "=== wger setup complete ==="
echo "=== Application URL: http://localhost ==="
echo "=== Admin credentials: admin / adminadmin ==="
