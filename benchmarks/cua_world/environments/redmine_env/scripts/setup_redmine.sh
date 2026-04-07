#!/bin/bash
# Redmine Setup Script (post_start hook)
# Starts Redmine via Docker Compose, runs initial configuration, and seeds realistic project data.

set -euo pipefail

echo "=== Setting up Redmine via Docker ==="

REDMINE_BASE_URL="http://localhost:3000"
REDMINE_LOGIN_URL="$REDMINE_BASE_URL/login"
REDMINE_DIR="/home/ga/redmine"
SEED_RESULT_VM="/tmp/redmine_seed_result.json"
# SECRET_KEY_BASE must be passed explicitly to docker exec (not inherited from docker-compose env vars)
REDMINE_SKB="redmine_env_secret_key_base_do_not_use_in_production_xyz123"

# ============================================================
# Helper: wait for HTTP readiness
# ============================================================
wait_for_http() {
  local url="$1"
  local timeout_sec="${2:-600}"
  local elapsed=0

  echo "Waiting for HTTP readiness: $url"

  while [ "$elapsed" -lt "$timeout_sec" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
    [ -z "$code" ] && code="000"

    if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "303" ]; then
      echo "HTTP ready after ${elapsed}s (HTTP $code)"
      return 0
    fi

    sleep 5
    elapsed=$((elapsed + 5))
    echo "  waiting... ${elapsed}s (HTTP $code)"
  done

  echo "ERROR: Timeout waiting for Redmine at $url"
  return 1
}

# ============================================================
# 1. Start Redmine containers
# ============================================================
echo "Setting up Docker Compose configuration..."
mkdir -p "$REDMINE_DIR"
cp /workspace/config/docker-compose.yml "$REDMINE_DIR/"
chown -R ga:ga "$REDMINE_DIR"

cd "$REDMINE_DIR"

echo "Starting Redmine containers..."
docker compose up -d

echo "Container status:"
docker compose ps

# ============================================================
# 2. Wait for Redmine to be reachable
# ============================================================
wait_for_http "$REDMINE_LOGIN_URL" 600

# Give Redmine a few more seconds to fully initialize after responding
sleep 10

# ============================================================
# 3. Load default data (trackers, statuses, priorities, roles)
# ============================================================
echo "Loading Redmine default data (trackers, statuses, priorities, roles)..."
# Pass SECRET_KEY_BASE explicitly — docker exec does not inherit docker-compose env vars
docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
  bash -c "RAILS_ENV=production REDMINE_LANG=en bundle exec rake redmine:load_default_data" \
  || echo "WARNING: load_default_data may have failed (possibly already loaded)"

sleep 3

# ============================================================
# 4. Run seed script (configure admin + seed data)
# ============================================================
echo "Running Redmine seed script..."

SEED_RB_HOST="/workspace/scripts/seed_redmine.rb"

if [ ! -f "$SEED_RB_HOST" ]; then
  echo "ERROR: Seed script not found at $SEED_RB_HOST"
  exit 1
fi

docker cp "$SEED_RB_HOST" redmine:/tmp/seed_redmine.rb

SEED_RAW="/tmp/redmine_seed_raw.log"
SEED_ERR="/tmp/redmine_seed_err.log"

docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
  bundle exec rails runner /tmp/seed_redmine.rb -e production \
  > "$SEED_RAW" 2> "$SEED_ERR"

# Extract the JSON result (lines starting with '{')
awk 'BEGIN{p=0} /^\{/ {p=1} p {print}' "$SEED_RAW" > "$SEED_RESULT_VM"

if ! jq . "$SEED_RESULT_VM" >/dev/null 2>&1; then
  echo "ERROR: Seed output is not valid JSON." >&2
  echo "--- Seed stdout (tail) ---" >&2
  tail -n 80 "$SEED_RAW" >&2 || true
  echo "--- Seed stderr (tail) ---" >&2
  tail -n 80 "$SEED_ERR" >&2 || true
  exit 1
fi

chmod 666 "$SEED_RESULT_VM" 2>/dev/null || true
cp "$SEED_RESULT_VM" /home/ga/redmine_seed_result.json 2>/dev/null || true
chown ga:ga /home/ga/redmine_seed_result.json 2>/dev/null || true
chmod 644 /home/ga/redmine_seed_result.json 2>/dev/null || true

echo "Seed result written: $SEED_RESULT_VM"

# Print summary
echo "Projects seeded: $(jq '.projects | length' "$SEED_RESULT_VM")"
echo "Users seeded: $(jq '.users | length' "$SEED_RESULT_VM")"
echo "Issues seeded: $(jq '.issues | length' "$SEED_RESULT_VM")"

# ============================================================
# 5. Configure Firefox profile
# ============================================================
setup_firefox_profile() {
  echo "Setting up Firefox profile..."

  local profile_root="/home/ga/.mozilla/firefox"
  local profile_dir="$profile_root/default.profile"

  sudo -u ga mkdir -p "$profile_dir"

  cat > "$profile_root/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

  cat > "$profile_dir/user.js" << 'USERJS'
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Disable updates
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Reduce promos/popups
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
USERJS

  chown -R ga:ga "$profile_root"
}

setup_firefox_profile

# ============================================================
# 6. Re-verify Redmine and warm-up Firefox
# ============================================================
echo "Re-verifying Redmine is responsive before launching Firefox..."
for i in $(seq 1 60); do
    if curl -s -o /dev/null -w "%{http_code}" "$REDMINE_LOGIN_URL" 2>/dev/null | grep -qE "200|302|303"; then
        echo "Redmine web service ready"
        break
    fi
    sleep 2
done

echo "Launching Firefox warm-up..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '$REDMINE_LOGIN_URL' > /tmp/firefox_warmup.log 2>&1 &"

# Wait up to 30s for the Firefox window to appear
FF_STARTED=false
for i in $(seq 1 30); do
  if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
    FF_STARTED=true
    echo "Firefox window detected after ${i}s"
    break
  fi
  sleep 1
done

if [ "$FF_STARTED" = "true" ]; then
  # Maximise the window
  sleep 1
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
  echo "Firefox warm-up complete"
else
  echo "WARNING: Firefox warm-up did not detect window within 30s; continuing anyway"
fi

echo ""
echo "=== Redmine setup complete ==="
echo "Redmine URL: $REDMINE_LOGIN_URL"
echo "Admin credentials: admin / Admin1234!"
echo "Seed mapping: $SEED_RESULT_VM"
