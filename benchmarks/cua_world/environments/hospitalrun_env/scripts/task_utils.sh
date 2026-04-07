#!/bin/bash
# Shared utilities for HospitalRun task scripts

# ─── Configuration ─────────────────────────────────────────────────────────
HR_URL="http://localhost:3000"
HR_COUCH_URL="http://couchadmin:test@localhost:5984"
HR_COUCH_MAIN_DB="main"
HR_USER="hradmin"
HR_PASS="test"

# ─── CouchDB helpers ──────────────────────────────────────────────────────
hr_couch_get() {
    local doc_id="$1"
    curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}"
}

hr_couch_put() {
    local doc_id="$1"
    local data="$2"
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}" \
        -H "Content-Type: application/json" \
        -d "$data"
}

hr_couch_post() {
    local data="$1"
    curl -s -X POST "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/" \
        -H "Content-Type: application/json" \
        -d "$data"
}

hr_couch_delete() {
    local doc_id="$1"
    local rev
    rev=$(hr_couch_get "$doc_id" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('_rev',''))" 2>/dev/null || echo "")
    if [ -n "$rev" ]; then
        curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}"
    fi
}

# Count documents of a type
hr_count_docs() {
    local type="$1"
    curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" \
        2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for row in data.get('rows', [])
            if row.get('doc', {}).get('type') == '$type')
print(count)
" 2>/dev/null || echo "0"
}

# Get document by patient ID field
hr_get_patient_by_id() {
    local patient_id="$1"
    curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" \
        2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    if doc.get('patientId') == '$patient_id' or doc.get('id') == '$patient_id':
        print(json.dumps(doc))
        break
" 2>/dev/null || echo "{}"
}

# ─── Screenshot ────────────────────────────────────────────────────────────
take_screenshot() {
    local outfile="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$outfile" 2>/dev/null || \
    DISPLAY=:1 import -window root "$outfile" 2>/dev/null || true
}

# ─── Firefox helpers ────────────────────────────────────────────────────────
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | awk '{print $1}' | head -1
}

focus_firefox() {
    local wid
    wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        sleep 0.5
    fi
}

navigate_firefox_to() {
    local url="$1"
    focus_firefox
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 20 --clearmodifiers "$url"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 3
}

# ─── Fix PouchDB LOADING state ───────────────────────────────────────────────
# ROOT CAUSE of permanent LOADING spinner:
#   _createRemoteDB() calls l.info() (GET /db/main). The main CouchDB database
#   has _security set to require the "user" role. Authentication is via OAuth
#   headers, which come from stored tokens in IndexedDB (pouch_config).
#   Since IndexedDB is cleared on each pre_task run, there are no OAuth tokens
#   on first boot. l.info() gets 401 → _createRemoteDB rejects → database.setup()
#   rejects → every route shows a permanent LOADING spinner.
#
# Fix 1: Remove CouchDB _security from the main database so l.info() succeeds
#   without OAuth tokens. This allows database.setup() to complete on the first
#   page load (before login). The validate_doc_update design doc still enforces
#   correct document format, but does not require authentication for writes.
#   After login, HospitalRun re-runs database.setup() with OAuth tokens,
#   creating a new authenticated PouchDB instance for all subsequent operations.
#
# Fix 2: Patch the JS bundle to bypass the ServiceWorker check so _createMainDB
#   always calls _createRemoteDB() (not the local offline-sync path).
#
# Fix 3: Remove SRI integrity attribute from index.html (after bundle patch,
#   SHA hash changes so SRI check fails → browser refuses to load bundle).
#
# Fix 4: Enter CouchDB admin party mode so design doc create/update works.
#
# Fix 5: Update CouchDB config docs as belt-and-suspenders.
#
# MUST be called BEFORE launching Firefox.
fix_offline_sync() {
    echo "[fix_offline_sync] Fixing PouchDB LOADING issue..."

    # ── Fix 1: Remove CouchDB main DB security restriction ──────────────────
    # This allows l.info() (GET /db/main) to succeed without OAuth auth headers,
    # so database.setup() completes on first page load even before login.
    curl -s -X PUT "${HR_COUCH_URL}/main/_security" \
        -H "Content-Type: application/json" \
        -d '{}' > /dev/null || true
    echo "[fix_offline_sync] Removed main DB security restriction (anonymous read/write allowed)"

    # ── Fix 2: Patch the JS bundle inside the Docker container ──────────────
    # Replace !e.config_disable_offline_sync&&navigator.serviceWorker? with
    # false&&navigator.serviceWorker? so _createMainDB always uses remote DB.
    # The patch is idempotent: checks for the GA_PATCHED marker comment.
    docker exec hospitalrun-app node -e "
var fs = require('fs'), path = require('path');
var dir = '/usr/src/app/node_modules/hospitalrun/prod/assets/';
var files = fs.readdirSync(dir).filter(function(f){ return f.match(/^hospitalrun-.*\\.js\$/); });
if (!files.length) { console.log('[patch] No bundle found'); process.exit(0); }
var bname = files[0];
var bundle = path.join(dir, bname);
var content = fs.readFileSync(bundle, 'utf8');
if (content.indexOf('/*GA_PATCHED*/') === 0) { console.log('[patch] Bundle already patched'); process.exit(0); }
var OLD = '!e.config_disable_offline_sync&&navigator.serviceWorker?';
var NEW = 'false&&navigator.serviceWorker?';
if (content.indexOf(OLD) === -1) { console.log('[patch] Pattern not found in bundle'); process.exit(0); }
var n = 0;
while (content.indexOf(OLD) !== -1) { content = content.replace(OLD, NEW); n++; }
content = '/*GA_PATCHED*/' + content;
fs.writeFileSync(bundle, content);
console.log('[patch] Bundle patched (' + n + ' occurrence(s)): ' + bname);
" 2>/dev/null || echo "[patch] node exec failed"

    # ── Fix 3: Remove SRI integrity attribute from index.html ───────────────
    # After patching the JS bundle (Fix 2), its SHA512 hash changes. Firefox's
    # Subresource Integrity (SRI) check compares the script's actual hash against
    # the integrity attribute in index.html. A mismatch causes the browser to
    # REFUSE to execute the bundle → the Ember app never initializes → LOADING forever.
    # Fix: remove the integrity attribute from the hospitalrun JS script tag.
    docker exec hospitalrun-app node -e "
var fs = require('fs');
var path = '/usr/src/app/node_modules/hospitalrun/prod/index.html';
var content = fs.readFileSync(path, 'utf8');
var patched = content.replace(/(src=\"\/assets\/hospitalrun-[^\"]*\.js\" )integrity=\"[^\"]*\"/, '\$1');
if (patched === content) {
    console.log('[sri-fix] integrity already removed or not found');
} else {
    fs.writeFileSync(path, patched);
    console.log('[sri-fix] Removed integrity attribute from hospitalrun JS script tag');
}
" 2>/dev/null || echo "[sri-fix] node exec failed"

    # ── Fix 4: Enter CouchDB admin party mode ───────────────────────────────
    # HospitalRun's database.setup() tries to create/update CouchDB design docs
    # on every page load. Design doc writes require admin privileges. By default,
    # even with _security={}, non-admin users get 403 "forbidden" on design docs.
    # Fix: delete the CouchDB admin user so CouchDB enters "admin party" mode,
    # where ALL users (including anonymous) are treated as admin. This allows
    # HospitalRun to create/update design docs without credentials.
    # The curl returns the old password hash on success, or "" if already deleted.
    docker exec hospitalrun-couchdb curl -s -X DELETE \
        "http://localhost:5984/_config/admins/couchadmin" \
        -u couchadmin:test 2>/dev/null | grep -q "pbkdf2\|sha256" && \
        echo "[admin-party] CouchDB admin user deleted, entered admin party mode" || \
        echo "[admin-party] CouchDB already in admin party mode (or delete failed)"

    # ── Fix 5: Update CouchDB config docs (belt-and-suspenders) ─────────────
    _upsert_couch_config() {
        local doc_id="$1"
        local value="$2"
        local doc rev
        doc=$(curl -s "${HR_COUCH_URL}/config/${doc_id}" 2>/dev/null || echo '{}')
        rev=$(echo "$doc" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('_rev',''))" 2>/dev/null || echo "")
        if [ -n "$rev" ]; then
            curl -s -X PUT "${HR_COUCH_URL}/config/${doc_id}" \
                -H "Content-Type: application/json" \
                -d "{\"_rev\":\"${rev}\",\"value\":${value}}" > /dev/null || true
        else
            curl -s -X PUT "${HR_COUCH_URL}/config/${doc_id}" \
                -H "Content-Type: application/json" \
                -d "{\"value\":${value}}" > /dev/null || true
        fi
    }

    _upsert_couch_config "config_disable_offline_sync" "true"
    _upsert_couch_config "config_external_search" "false"

    # Patch config.js so future container restarts also use the correct value.
    docker exec hospitalrun-app bash -c '
        if grep -q "disableOfflineSync" /usr/src/app/config.js; then
            echo "config.js already patched"
        else
            sed -i "s/config\.serverInfo/config.disableOfflineSync = true;\nconfig.serverInfo/" /usr/src/app/config.js
            echo "config.js patched"
        fi
    ' 2>/dev/null || true

    echo "[fix_offline_sync] Done"
}

# ─── Ensure Firefox is fresh and HospitalRun is logged in ───────────────────
# This kills any existing Firefox (which may have stale PouchDB state from the
# checkpoint), applies the offline sync fix, then relaunches Firefox and logs in.
ensure_hospitalrun_logged_in() {
    # Step 1: Kill any existing Firefox so PouchDB restarts clean
    echo "Killing existing Firefox..."
    pkill -9 -f firefox 2>/dev/null || true
    sleep 3
    # Remove stale lock files that would prevent Firefox from starting
    find /home/ga/.mozilla -name "*.lock" 2>/dev/null | xargs rm -f 2>/dev/null || true
    find /home/ga/.mozilla -name ".parentlock" 2>/dev/null | xargs rm -f 2>/dev/null || true

    # Clear Firefox's IndexedDB for localhost:3000 to eliminate stale PouchDB data.
    # PouchDB stores its local database in Firefox's storage/default/http+++localhost+3000/
    # directory. Deleting this ensures Firefox starts with no local PouchDB database,
    # so it cannot do a local sync (even if disableOfflineSync somehow fails).
    echo "Clearing Firefox IndexedDB for localhost:3000..."
    find /home/ga/.mozilla/firefox -type d -name "http+++localhost+3000*" 2>/dev/null | \
        xargs rm -rf 2>/dev/null || true
    find /home/ga/.mozilla/firefox -path "*/storage/default/http+++localhost+3000*" 2>/dev/null | \
        xargs rm -rf 2>/dev/null || true

    # Clear Firefox's HTTP disk cache so the JS bundle patch is served fresh.
    # Without this, Firefox may serve the old (unpatched) bundle from its cache,
    # bypassing the fix_offline_sync JS bundle patch.
    find /home/ga/.mozilla/firefox -name "cache2" -type d 2>/dev/null | \
        xargs rm -rf 2>/dev/null || true
    find /home/ga/snap/firefox -name "cache2" -type d 2>/dev/null | \
        xargs rm -rf 2>/dev/null || true

    # Also clear snap Firefox's Service Worker Cache API and IndexedDB for localhost:3000.
    # CRITICAL: The service worker caches the original index.html (with SRI integrity
    # attribute). After we patch the JS bundle (Fix 2) + remove the SRI integrity attr
    # (Fix 3), the SW-cached old index.html (still has integrity) gets served, causing
    # the SRI hash mismatch error → browser refuses to execute the patched bundle.
    # The SW cache is in snap Firefox's storage (NOT in /home/ga/.mozilla/firefox),
    # so the above find commands missed it. Deleting the entire http+++localhost+3000
    # directory clears the SW cache, IndexedDB (PouchDB), and LocalStorage.
    find /home/ga/snap/firefox -type d -name "http+++localhost+3000" 2>/dev/null | \
        xargs rm -rf 2>/dev/null || true
    find /home/ga/snap/firefox -path "*/storage/default/http+++localhost+3000*" 2>/dev/null | \
        xargs rm -rf 2>/dev/null || true
    echo "Cleared snap Firefox service worker cache and storage for localhost:3000"

    # Step 2: Apply the PouchDB offline sync fix BEFORE Firefox opens
    fix_offline_sync

    # Step 2.5: Write/refresh Firefox user.js to suppress the "Save password?" dialog.
    # This must be done before Firefox launches so the pref takes effect immediately.
    local ff_profile_dir=""
    if [ -d /home/ga/snap/firefox/common/.mozilla/firefox ]; then
        ff_profile_dir=$(find /home/ga/snap/firefox/common/.mozilla/firefox \
            -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
    fi
    if [ -z "$ff_profile_dir" ] && [ -d /home/ga/.mozilla/firefox ]; then
        ff_profile_dir=$(find /home/ga/.mozilla/firefox \
            -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
    fi
    if [ -n "$ff_profile_dir" ]; then
        cat > "${ff_profile_dir}/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage", "http://localhost:3000");
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("network.prefetch-next", false);
user_pref("browser.download.manager.showWhenStarting", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_tabs_undo", 0);
// Disable Subresource Integrity (SRI) checks. We patch the hospitalrun JS bundle
// to fix the offline sync LOADING bug, which changes its SHA512 hash. Rather than
// maintaining correct hashes, we disable SRI so Firefox loads the patched bundle.
user_pref("security.sri.enabled", false);
FFEOF
        chown ga:ga "${ff_profile_dir}/user.js" 2>/dev/null || true
        echo "Firefox user.js refreshed (signon.rememberSignons=false)"
    fi

    # Step 3: Launch Firefox fresh at HospitalRun
    # Try as current user first; fall back to su - ga (handles both root and ga contexts)
    echo "Launching Firefox..."
    (DISPLAY=:1 firefox http://localhost:3000 &>/dev/null &) 2>/dev/null || \
    su - ga -c "DISPLAY=:1 firefox http://localhost:3000 &" 2>/dev/null || true
    disown 2>/dev/null || true

    # Wait for the Firefox window to appear
    local wid
    for i in $(seq 1 25); do
        sleep 2
        wid=$(get_firefox_window_id)
        if [ -n "$wid" ]; then
            echo "Firefox window found (attempt $i)"
            break
        fi
    done
    sleep 2
    focus_firefox
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 3  # Let HospitalRun app initialize in the browser

    # Step 4: Login
    # Navigate explicitly to root to trigger the login route.
    # With fix_offline_sync() removing the main DB security restriction,
    # database.setup() now succeeds before login (l.info() returns 200),
    # so the login form renders immediately without LOADING spinner.
    navigate_firefox_to "http://localhost:3000"
    sleep 8  # Wait for the login form to render (Ember boots + database.setup())

    # Fill in credentials
    # Username field at ~994,354 (1920x1080); password Tab from there
    DISPLAY=:1 xdotool mousemove 994 354 click 1
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.2
    DISPLAY=:1 xdotool type --delay 30 --clearmodifiers 'hradmin'
    sleep 0.3
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --delay 30 --clearmodifiers 'test'
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 20  # Wait for login to fully complete: OAuth tokens stored, app transitions

    # ── Post-login reload to ensure clean authenticated state ─────────────────
    # After login, HospitalRun stores OAuth tokens and re-runs database.setup().
    # Reloading the page ensures a clean boot with session restored from localStorage
    # and database.setup() re-running with the full authenticated session.
    # NOTE: The "Save password?" dialog is suppressed by user.js (signon.rememberSignons=false).
    # We do NOT press Escape here as that could interfere with Ember route transitions.
    echo "Reloading Firefox to ensure clean authenticated session..."
    navigate_firefox_to "http://localhost:3000"
    sleep 25  # Wait for Ember app to re-init with session, database.setup() to complete

    echo "Login complete"
}

# Wait for HospitalRun's PouchDB database to fully connect and the patients list
# to load. This must be called AFTER ensure_hospitalrun_logged_in. It navigates
# to #/patients and waits up to 40 seconds for the LOADING spinner to resolve.
# After this returns, subsequent navigations to other routes render immediately
# because database.setup() has already completed.
wait_for_db_ready() {
    # database.setup() was already triggered by the post-login reload in
    # ensure_hospitalrun_logged_in(). Navigate to #/patients and wait a short
    # time for the Ember route model (allDocs on mainDB) to resolve.
    echo "Navigating to patients list..."
    navigate_firefox_to "http://localhost:3000/#/patients"
    sleep 20
    echo "Patients list ready"
}

# Type text safely with xdotool
xdotype() {
    DISPLAY=:1 xdotool type --delay 50 --clearmodifiers "$1"
}

# ─── Ensure HospitalRun Docker services are running ──────────────────────
# Critical when loading from QEMU checkpoint — Docker containers that were
# running during checkpoint creation are NOT running when restored.
# Also re-applies the PouchDB JS bundle patch (Fix 2/3) since container
# restarts lose the in-memory filesystem patches.
ensure_hospitalrun_running() {
    # Quick check: is HospitalRun already responding?
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$HR_URL" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        echo "HospitalRun already running (HTTP $http_code)"
        return 0
    fi

    echo "HospitalRun not responding (HTTP $http_code). Starting services..."

    # Ensure Docker daemon is running
    systemctl is-active docker >/dev/null 2>&1 || {
        echo "Starting Docker daemon..."
        systemctl start docker
        sleep 5
    }

    # Ensure vm.max_map_count for Elasticsearch
    sysctl -w vm.max_map_count=262144 2>/dev/null || true

    # Start containers
    local HR_DIR="/home/ga/hospitalrun"
    if [ -f "$HR_DIR/docker-compose.yml" ]; then
        echo "Starting HospitalRun containers..."
        cd "$HR_DIR"
        docker compose up -d 2>&1 || docker-compose up -d 2>&1 || true
        cd - >/dev/null
    else
        echo "ERROR: docker-compose.yml not found at $HR_DIR"
        return 1
    fi

    # Wait for CouchDB first (port 5984)
    echo "Waiting for CouchDB..."
    local elapsed=0
    while [ "$elapsed" -lt 60 ]; do
        if curl -s "http://localhost:5984/" >/dev/null 2>&1; then
            echo "CouchDB ready after ${elapsed}s"
            break
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done

    # Wait for HospitalRun app (port 3000)
    echo "Waiting for HospitalRun app..."
    elapsed=0
    while [ "$elapsed" -lt 120 ]; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$HR_URL" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
            echo "HospitalRun is ready after ${elapsed}s (HTTP $http_code)"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting for HospitalRun... ${elapsed}s (HTTP $http_code)"
        fi
    done

    # Re-apply PouchDB patches (lost on container restart)
    echo "Re-applying PouchDB offline sync fix..."
    fix_offline_sync

    return 0
}

# Auto-start services when task_utils.sh is sourced
ensure_hospitalrun_running

echo "HospitalRun task utilities loaded"
