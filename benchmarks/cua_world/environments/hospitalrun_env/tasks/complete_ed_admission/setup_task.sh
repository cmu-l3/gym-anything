#!/bin/bash
echo "=== Setting up complete_ed_admission task ==="

source /workspace/scripts/task_utils.sh

# ── Verify HospitalRun is running ─────────────────────────────────────────
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    echo "Waiting for HospitalRun (attempt $i)..."
    sleep 5
done

# ── Clean up any previous David Nakamura records (idempotent) ─────────────
echo "Cleaning up any previous David Nakamura data..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json, urllib.request, urllib.parse
data = json.load(sys.stdin)
couch_url = 'http://couchadmin:test@localhost:5984'
db = 'main'
deleted = 0
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design'):
        continue
    d = doc.get('data', doc)
    doc_str = json.dumps(doc).lower()
    # Only match David Nakamura (NOT Linda Nakamura who is a pre-seeded patient)
    is_david_nakamura = (
        (d.get('lastName', '').lower() == 'nakamura' and d.get('firstName', '').lower() == 'david')
        or ('nakamura' in doc_str and 'david' in doc_str)
    )
    if not is_david_nakamura:
        # Also check linked documents (e.g. visit/vitals referencing a david nakamura patient)
        patient_ref = d.get('patient', doc.get('patient', ''))
        if not ('nakamura' in patient_ref.lower() and 'david' in json.dumps(doc).lower()):
            continue
    rev = doc.get('_rev', '')
    if rev:
        req = urllib.request.Request(
            f'{couch_url}/{db}/{doc_id}?rev={urllib.parse.quote(rev)}',
            method='DELETE'
        )
        try:
            urllib.request.urlopen(req, timeout=5)
            deleted += 1
        except:
            pass
print(f'Deleted {deleted} previous Nakamura documents')
" 2>/dev/null || true

# Also clean up any appointments with the follow-up reason
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json, urllib.request, urllib.parse
data = json.load(sys.stdin)
couch_url = 'http://couchadmin:test@localhost:5984'
db = 'main'
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design'):
        continue
    d = doc.get('data', doc)
    reason = d.get('reasonForAppointment', d.get('reason', ''))
    if 'cardiac risk stratification' in reason.lower():
        rev = doc.get('_rev', '')
        if rev:
            req = urllib.request.Request(
                f'{couch_url}/{db}/{doc_id}?rev={urllib.parse.quote(rev)}',
                method='DELETE'
            )
            try:
                urllib.request.urlopen(req, timeout=5)
            except:
                pass
" 2>/dev/null || true

# ── Delete stale output files BEFORE recording timestamp ──────────────────
rm -f /tmp/complete_ed_admission_result.json
rm -f /tmp/complete_ed_admission_start.png
rm -f /tmp/complete_ed_admission_end.png

# ── Record baseline ───────────────────────────────────────────────────────
date +%s > /tmp/task_start_timestamp

INITIAL_DOC_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('total_rows', 0))
" 2>/dev/null || echo "0")
echo "$INITIAL_DOC_COUNT" > /tmp/initial_doc_count

# ── Phase 1: PouchDB initialization (admin party mode) ────────────────────
# HospitalRun's PouchDB needs to write design docs on first page load.
# CouchDB requires admin for design doc writes. The fix_offline_sync function
# enters admin party mode (deletes CouchDB admin) so PouchDB can write.
# We also need _security={} so anonymous l.info() succeeds.
echo "Phase 1: Initializing PouchDB (admin party mode)..."

# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 3

# Clear Firefox IndexedDB/cache for clean PouchDB state
find /home/ga -path "*http+++localhost+3000*" -exec rm -rf {} + 2>/dev/null || true
find /home/ga -name "cache2" -type d -exec rm -rf {} + 2>/dev/null || true
find /home/ga/snap/firefox -type d -name "http+++localhost+3000" -exec rm -rf {} + 2>/dev/null || true
find /home/ga/snap/firefox -path "*/storage/default/http+++localhost+3000*" -exec rm -rf {} + 2>/dev/null || true
find /home/ga/.mozilla -name "*.lock" -delete 2>/dev/null || true
find /home/ga/.mozilla -name ".parentlock" -delete 2>/dev/null || true

# Apply PouchDB fixes (admin party + _security + JS bundle patch + SRI)
fix_offline_sync

# Write Firefox user.js to suppress password dialog and disable SRI
FF_PROFILE_DIR=""
if [ -d /home/ga/snap/firefox/common/.mozilla/firefox ]; then
    FF_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox \
        -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi
if [ -z "$FF_PROFILE_DIR" ] && [ -d /home/ga/.mozilla/firefox ]; then
    FF_PROFILE_DIR=$(find /home/ga/.mozilla/firefox \
        -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi
if [ -n "$FF_PROFILE_DIR" ]; then
    cat > "${FF_PROFILE_DIR}/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage", "http://localhost:3000");
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_tabs_undo", 0);
user_pref("security.sri.enabled", false);
FFEOF
    chown ga:ga "${FF_PROFILE_DIR}/user.js" 2>/dev/null || true
fi

# Launch Firefox in admin party mode so PouchDB can write design docs
echo "Launching Firefox for PouchDB initialization..."
su - ga -c "DISPLAY=:1 nohup firefox http://localhost:3000 &>/dev/null &" 2>/dev/null || \
    (DISPLAY=:1 firefox http://localhost:3000 &>/dev/null &) 2>/dev/null || true
disown 2>/dev/null || true

# Wait for Firefox window
for i in $(seq 1 25); do
    sleep 2
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        echo "Firefox window found (attempt $i)"
        break
    fi
done
sleep 2
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Wait for PouchDB database.setup() to complete in admin party mode
# This step allows PouchDB to write design documents to CouchDB
echo "Waiting for PouchDB database.setup()..."
sleep 30

# ── Phase 2: Restore admin and login ──────────────────────────────────────
# Now that PouchDB has completed setup (design docs written), restore the
# CouchDB admin so the HospitalRun server can authenticate users.
echo "Phase 2: Restoring CouchDB admin for login..."
docker exec hospitalrun-couchdb curl -s -X PUT \
    "http://localhost:5984/_config/admins/couchadmin" \
    -d '"test"' > /dev/null 2>&1 || true

# Re-apply _security={} (admin restoration may have re-restricted it)
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_security" \
    -H "Content-Type: application/json" \
    -d '{}' > /dev/null || true
echo "CouchDB admin restored, _security cleared"

# Login (do NOT restart Firefox — keep PouchDB IndexedDB state intact)
echo "Logging in..."
navigate_firefox_to "http://localhost:3000/#/login"
sleep 8

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
sleep 20

# Dismiss save-password dialog if it appears
DISPLAY=:1 xdotool key Escape
sleep 2

# Post-login reload for clean session
navigate_firefox_to "http://localhost:3000"
sleep 25

echo "Login complete"

# ── Navigate to new patient registration form ─────────────────────────────
echo "Navigating to New Patient registration form..."
navigate_firefox_to "http://localhost:3000/#/patients/edit/new"
sleep 20  # Wait for Ember.js route to render the new patient form

# ── Take start screenshot ─────────────────────────────────────────────────
take_screenshot /tmp/complete_ed_admission_start.png
echo "Task start state screenshot saved."

echo "=== complete_ed_admission setup complete ==="
echo "Agent sees: HospitalRun new patient registration form (or login page)"
echo "Task: Register David Nakamura, create ED visit, record vitals, add diagnosis, order labs/imaging, prescribe medication, schedule follow-up"
