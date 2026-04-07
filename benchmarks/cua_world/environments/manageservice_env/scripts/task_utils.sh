#!/bin/bash
# ManageEngine ServiceDesk Plus Task Utilities
#
# Source this file at the top of each setup_task.sh:
#   source /workspace/scripts/task_utils.sh
#
# Main entry point for task setup:
#   ensure_sdp_running   -> waits for install, starts SDP, prepares initial data
#   sdp_db_exec "SQL"    -> run SQL against SDP's bundled PostgreSQL
#   ensure_firefox_on_sdp -> launch Firefox on SDP home page

SDP_HOME="/opt/ManageEngine/ServiceDesk"
SDP_PORT="8080"
SDP_BASE_URL="https://localhost:${SDP_PORT}"
SDP_LOGIN_URL="${SDP_BASE_URL}/j_security_check"
INSTALL_MARKER="/tmp/sdp_install_complete.marker"
SERVICE_MARKER="/tmp/sdp_service_ready.marker"
SETUP_MUTEX="/tmp/sdp_setup_mutex"
SETUP_LOG="/tmp/sdp_setup.log"
PSQL_BIN="$SDP_HOME/pgsql/bin/psql"
DB_PORT="65432"
DB_NAME="servicedesk"

log() { echo "[$(date '+%H:%M:%S')] [sdp] $*" | tee -a "$SETUP_LOG"; }

# ==============================================================================
# sdp_db_exec: Execute SQL against SDP's bundled PostgreSQL
# Uses postgres unix user peer authentication (no password required)
# ==============================================================================
sdp_db_exec() {
    local sql="$1"
    local db="${2:-$DB_NAME}"
    su - postgres -c "\"$PSQL_BIN\" -h 127.0.0.1 -p $DB_PORT -d \"$db\" -t -A -c \"$sql\"" 2>/dev/null || \
    PGPASSWORD="" "$PSQL_BIN" -h 127.0.0.1 -p "$DB_PORT" -U postgres -d "$db" -t -A -c "$sql" 2>/dev/null || \
    PGPASSWORD="" "$PSQL_BIN" -h 127.0.0.1 -p "$DB_PORT" -U sdpadmin -d "$db" -t -A -c "$sql" 2>/dev/null
}

# ==============================================================================
# wait_for_sdp_install: Wait for background installer to finish
# ==============================================================================
wait_for_sdp_install() {
    local max_wait="${1:-3000}"
    local waited=0

    if [ -f "$INSTALL_MARKER" ] && [ "$(cat "$INSTALL_MARKER" 2>/dev/null)" = "OK" ]; then
        log "Install already complete."
        return 0
    fi

    log "Waiting for SDP install (up to ${max_wait}s)..."
    while true; do
        if [ -f "$INSTALL_MARKER" ]; then
            local content
            content=$(cat "$INSTALL_MARKER" 2>/dev/null)
            if [ "$content" = "OK" ]; then
                log "Install complete after ${waited}s"
                return 0
            else
                log "ERROR: Install failed: $content"
                return 1
            fi
        fi
        sleep 15
        waited=$((waited + 15))
        if [ $waited -ge $max_wait ]; then
            log "ERROR: Install timed out after ${waited}s"
            cat /tmp/sdp_install.log 2>/dev/null | tail -20 >> "$SETUP_LOG"
            return 1
        fi
        if [ $((waited % 60)) -eq 0 ]; then
            local progress
            progress=$(tail -3 /tmp/sdp_install.log 2>/dev/null | tr '\n' ' ')
            log "  Install progress (~${waited}s): $progress"
        fi
    done
}

# ==============================================================================
# fix_pgsql_permissions: Fix PostgreSQL directory and user permissions
# ==============================================================================
fix_pgsql_permissions() {
    log "Fixing PostgreSQL permissions..."

    if [ ! -d "$SDP_HOME/pgsql" ]; then
        log "WARNING: pgsql dir not found at $SDP_HOME/pgsql"
        return 1
    fi

    # Allow postgres user to access binaries
    chmod 755 "$SDP_HOME" 2>/dev/null || true
    chmod 755 "$SDP_HOME/pgsql" 2>/dev/null || true
    chmod 755 "$SDP_HOME/pgsql/bin" 2>/dev/null || true
    chmod 755 "$SDP_HOME/pgsql/lib" 2>/dev/null || true
    chmod 755 "$SDP_HOME/pgsql/share" 2>/dev/null || true
    chmod -R a+rX "$SDP_HOME/pgsql/bin/" 2>/dev/null || true
    chmod -R a+rX "$SDP_HOME/pgsql/lib/" 2>/dev/null || true
    chmod -R a+rX "$SDP_HOME/pgsql/share/" 2>/dev/null || true

    # Data dir must be owned by postgres
    if [ -d "$SDP_HOME/pgsql/data" ]; then
        chown -R postgres:postgres "$SDP_HOME/pgsql/data" 2>/dev/null || true
        chmod 700 "$SDP_HOME/pgsql/data" 2>/dev/null || true
    fi

    # Fix postgres user home (SDP may have set it to inaccessible pgsql dir)
    if ! id postgres &>/dev/null; then
        useradd -r -s /bin/bash -d /var/lib/postgresql postgres 2>/dev/null || true
    fi
    mkdir -p /var/lib/postgresql
    usermod -d /var/lib/postgresql postgres 2>/dev/null || true
    chown postgres:postgres /var/lib/postgresql 2>/dev/null || true
    chmod 700 /var/lib/postgresql 2>/dev/null || true

    log "PostgreSQL permissions fixed."
}

# ==============================================================================
# start_sdp: Start the SDP service
# ==============================================================================
start_sdp() {
    log "Starting SDP service..."

    pkill -f "WrapperJVMMain" 2>/dev/null || true
    pkill -f "wrapper.java" 2>/dev/null || true
    pkill -f "PSEM" 2>/dev/null || true
    sleep 3

    local run_script=""
    for s in run.sh startServiceDesk.sh wrapper; do
        if [ -f "$SDP_HOME/bin/$s" ]; then
            run_script="$s"
            break
        fi
    done

    if [ -z "$run_script" ]; then
        log "ERROR: No start script found in $SDP_HOME/bin"
        ls "$SDP_HOME/bin/" 2>/dev/null >> "$SETUP_LOG"
        return 1
    fi

    log "Starting via $run_script..."
    (cd "$SDP_HOME/bin" && nohup bash "$run_script" > /tmp/sdp_start.log 2>&1 &)
    log "SDP started (PID group $!)"
}

# ==============================================================================
# wait_for_sdp_https: Wait for SDP HTTPS endpoint to respond
# ==============================================================================
wait_for_sdp_https() {
    local max_wait="${1:-600}"
    local waited=0
    local url="${SDP_BASE_URL}/ManageEngine/Login.do"

    log "Waiting for SDP HTTPS on port $SDP_PORT (up to ${max_wait}s)..."

    while [ $waited -lt $max_wait ]; do
        local http_code
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "301" ]; then
            log "SDP is up! (HTTP $http_code after ${waited}s)"
            return 0
        fi
        sleep 10
        waited=$((waited + 10))
        if [ $((waited % 60)) -eq 0 ]; then
            log "  SDP wait: ${waited}s (HTTP: $http_code)"
            tail -3 /tmp/sdp_start.log 2>/dev/null >> "$SETUP_LOG" || true
        fi
    done

    log "WARNING: SDP not responding after ${max_wait}s"
    ss -tlnp | grep "$SDP_PORT" >> "$SETUP_LOG" 2>&1 || true
    return 1
}

# ==============================================================================
# clear_mandatory_password_change: Allow login without forced password change
# ==============================================================================
clear_mandatory_password_change() {
    log "Clearing mandatory password change flag..."
    local result
    result=$(sdp_db_exec "UPDATE aaapasswordstatus SET change_pwd_on_login = false WHERE account_id IN (SELECT a.account_id FROM aaaaccount a JOIN aaalogin l ON l.login_id = a.login_id WHERE LOWER(l.name) = 'administrator');" 2>&1)
    log "Password status update: $result"
}

# ==============================================================================
# get_sdp_api_key_from_db: Get administrator API key from database
# ==============================================================================
get_sdp_api_key_from_db() {
    local key
    # Try adsauthtokens table (SDP 14+)
    key=$(sdp_db_exec "SELECT auth_token FROM adsauthtokens WHERE user_id = (SELECT account_id FROM aaaaccount a JOIN aaalogin l ON l.login_id = a.login_id WHERE LOWER(l.name) = 'administrator' LIMIT 1) ORDER BY created_time DESC LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$key" ] && [ ${#key} -gt 20 ]; then
        echo "$key"
        return 0
    fi
    # Try adskeybasedauthcredentials (SDP 14.x)
    key=$(sdp_db_exec "SELECT auth_token FROM adskeybasedauthcredentials WHERE auth_credential_id = (SELECT account_id FROM aaaaccount a JOIN aaalogin l ON l.login_id = a.login_id WHERE LOWER(l.name) = 'administrator' LIMIT 1) LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$key" ] && [ ${#key} -gt 20 ]; then
        echo "$key"
        return 0
    fi
    echo ""
}

# ==============================================================================
# generate_api_key_via_web: Login via Python RSA and generate API key
# ==============================================================================
generate_api_key_via_web() {
    python3 /tmp/sdp_login.py 2>/dev/null || true
}

# ==============================================================================
# write_python_login_script: Write Python helper for RSA login
# ==============================================================================
write_python_login_script() {
    cat > /tmp/sdp_login.py << 'PYEOF'
#!/usr/bin/env python3
"""
Login to ManageEngine ServiceDesk Plus and generate/retrieve API key.
Handles RSA-encrypted password (SDP encrypts passwords before submission).
"""
import sys, os, re, json, base64, requests
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

BASE = "https://localhost:8080"
USER = "administrator"
PASS = "Admin1234!"
PASS_ALT = "administrator"

def get_rsa_pubkey(html):
    """Extract RSA public key from SDP login page."""
    patterns = [
        r'id=["\']pubkey["\'][^>]*value=["\']([^"\']+)["\']',
        r'value=["\']([A-Za-z0-9+/=]{100,})["\'][^>]*id=["\']pubkey["\']',
        r'var\s+pubKey\s*=\s*["\']([^"\']+)["\']',
        r'"pubkey"\s*:\s*"([^"]+)"',
        r"'pubkey'\s*,\s*'([^']+)'",
    ]
    for pat in patterns:
        m = re.search(pat, html, re.IGNORECASE)
        if m and len(m.group(1)) > 50:
            return m.group(1)
    return None

def rsa_encrypt(pubkey_b64, plaintext):
    """RSA PKCS1v15 encrypt with public key."""
    try:
        from Crypto.PublicKey import RSA
        from Crypto.Cipher import PKCS1_v1_5
        key_der = base64.b64decode(pubkey_b64)
        pub_key = RSA.import_key(key_der)
        cipher = PKCS1_v1_5.new(pub_key)
        encrypted = cipher.encrypt(plaintext.encode('utf-8'))
        return base64.b64encode(encrypted).decode('ascii')
    except Exception as e:
        print(f"RSA encrypt error: {e}", file=sys.stderr)
        return plaintext

def try_login(session, password):
    """Attempt login with given password, returns (success, on_change_page)."""
    try:
        r_login = session.get(f"{BASE}/ManageEngine/Login.do", verify=False, timeout=30)
        pubkey = get_rsa_pubkey(r_login.text)
        enc_pass = rsa_encrypt(pubkey, password) if pubkey else password

        r = session.post(
            f"{BASE}/j_security_check",
            data={'j_username': USER, 'j_password': enc_pass},
            verify=False, allow_redirects=True, timeout=30
        )
        is_on_change = 'changePwd' in r.url or 'ChangePassword' in r.url or 'changepwd' in r.text.lower()
        login_ok = ('loginError' not in r.text or 'loginError = "false"' in r.text or 'loginError=false' in r.url) and 'Login.do' not in r.url
        return login_ok, is_on_change, pubkey, r
    except Exception as e:
        print(f"Login error: {e}", file=sys.stderr)
        return False, False, None, None

def get_api_key(session):
    """Try to retrieve API key from various SDP endpoints."""
    endpoints = [
        "/ManageEngine/OPAds.do?reqType=getAPIKey",
        "/ManageEngine/OPAds.do?reqType=getUserAPIKey",
        "/api/v3/users/me",
    ]
    for ep in endpoints:
        try:
            r = session.get(f"{BASE}{ep}", verify=False, timeout=10)
            m = re.search(r'"api[_]?[kK]ey"\s*:\s*"([^"]{20,})"', r.text)
            if m:
                return m.group(1)
            # JSON response
            try:
                data = r.json()
                key = data.get('api_key') or data.get('apiKey') or data.get('authtoken')
                if key and len(str(key)) > 20:
                    return str(key)
            except:
                pass
        except:
            pass
    return None

def generate_api_key(session):
    """Generate a new API key."""
    try:
        r = session.post(
            f"{BASE}/ManageEngine/OPAds.do",
            data={'reqType': 'generateAPIKey'},
            verify=False, timeout=10
        )
        m = re.search(r'"([a-f0-9\-]{30,})"', r.text)
        if m:
            return m.group(1)
    except:
        pass
    return None

if __name__ == "__main__":
    session = requests.Session()

    # Try login with original password
    ok, on_change, pubkey, resp = try_login(session, PASS)

    if not ok and on_change:
        print("Mandatory password change page, trying password change...", file=sys.stderr)
        # Change password
        if pubkey:
            old_enc = rsa_encrypt(pubkey, PASS)
            new_enc = rsa_encrypt(pubkey, PASS_ALT)
        else:
            old_enc, new_enc = PASS, PASS_ALT
        try:
            session.post(
                f"{BASE}/ManageEngine/OPAds.do",
                data={
                    'reqType': 'changepassword',
                    'oldPassword': old_enc,
                    'newPassword': new_enc,
                    'confirmPassword': new_enc,
                },
                verify=False, allow_redirects=True, timeout=30
            )
        except:
            pass
        # Retry login with new password
        session = requests.Session()
        ok, _, _, _ = try_login(session, PASS_ALT)
        if not ok:
            ok, _, _, _ = try_login(session, PASS)

    if not ok:
        print("Login failed with all passwords", file=sys.stderr)
        sys.exit(1)

    print("Login successful", file=sys.stderr)

    # Get or generate API key
    api_key = get_api_key(session) or generate_api_key(session)
    if api_key:
        with open('/tmp/sdp_api_key.txt', 'w') as f:
            f.write(api_key)
        print(f"API key saved: {api_key[:10]}...", file=sys.stderr)
        print(api_key)
    else:
        print("Could not get API key", file=sys.stderr)
        sys.exit(1)
PYEOF
    chmod +x /tmp/sdp_login.py
}

# ==============================================================================
# sdp_api_get: Authenticated GET to SDP REST API
# ==============================================================================
sdp_api_get() {
    local endpoint="$1"
    local api_key="${2:-$(cat /tmp/sdp_api_key.txt 2>/dev/null)}"
    curl -sk -H "authtoken: $api_key" "${SDP_BASE_URL}${endpoint}" 2>/dev/null
}

# ==============================================================================
# sdp_api_post: Authenticated POST to SDP REST API
# ==============================================================================
sdp_api_post() {
    local endpoint="$1"
    local data="$2"
    local api_key="${3:-$(cat /tmp/sdp_api_key.txt 2>/dev/null)}"
    curl -sk -X POST \
        -H "authtoken: $api_key" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "input_data=$data" \
        "${SDP_BASE_URL}${endpoint}" 2>/dev/null
}

# ==============================================================================
# create_initial_requests: Create sample service requests via direct DB INSERT
# CRITICAL: Must set templateid=1 and duebytime for SDP UI to render requests
# statusdefinition: 2=Open; prioritydefinition: 1=Low,3=Medium,4=High
# categorydefinition: 2=Desktop Hardware, 3=Software, 10=Network
# sduser IDs 6-10 are the pre-created requesters (Alex Johnson, etc.)
# Emily Davis (ID 14) is created explicitly for the create_request task
# ==============================================================================
create_initial_requests() {
    log "Creating initial service requests via DB..."

    # Ensure Emily Davis exists for the create_request task
    local emily_count
    emily_count=$(sdp_db_exec "SELECT COUNT(*) FROM sduser WHERE firstname='Emily' AND lastname='Davis';" 2>/dev/null | tr -d '[:space:]')
    if [ "${emily_count:-0}" -eq 0 ]; then
        local emily_id
        emily_id=$(sdp_db_exec "SELECT COALESCE(MAX(user_id),13)+1 FROM aaauser;" 2>/dev/null | tr -d '[:space:]')
        emily_id="${emily_id:-14}"
        sdp_db_exec "INSERT INTO aaauser (user_id, first_name, last_name, createdtime, description) VALUES (${emily_id}, 'Emily', 'Davis', 1771800000000, 'Requester') ON CONFLICT (user_id) DO NOTHING;" 2>/dev/null || true
        sdp_db_exec "INSERT INTO sduser (userid, firstname, lastname, status, typeid, employeeid) VALUES (${emily_id}, 'Emily', 'Davis', 'ACTIVE', 1, 'EMP0${emily_id}') ON CONFLICT (userid) DO NOTHING;" 2>/dev/null || true
        log "Emily Davis created with ID $emily_id"
    fi

    # Check if requests already exist
    local count
    count=$(sdp_db_exec "SELECT COUNT(*) FROM workorder WHERE workorderid IN (1001,1002,1003,1004,1005);" 2>/dev/null | tr -d '[:space:]')
    if [ "${count:-0}" -eq 5 ]; then
        log "Initial requests already exist (count=$count)."
        return 0
    fi

    # Get administrator account_id (typically 2)
    local admin_id
    admin_id=$(sdp_db_exec "SELECT account_id FROM aaaaccount a JOIN aaalogin l ON l.login_id = a.login_id WHERE LOWER(l.name) = 'administrator' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    admin_id="${admin_id:-2}"

    # Use creation time ~1 week ago; due time = creation + 3 days
    # templateid=1 (Default Request) is REQUIRED for SDP UI to render the rows
    # Request titles match task.json descriptions exactly
    sdp_db_exec "
INSERT INTO workorder (workorderid, requesterid, createdbyid, createdtime, duebytime, modeid, helpdeskid, isparent, templateid, title, description) VALUES
(1001, 6, ${admin_id}, 1771771650000, 1772030850000, 2, 1, true, 1, 'Laptop keyboard not responding', 'Keys are unresponsive after recent Windows update. All keys affected.'),
(1002, 7, ${admin_id}, 1771771660000, 1772030860000, 2, 1, true, 1, 'Email account not working - cannot send or receive emails', 'SMTP connection errors when sending emails. Receiving works fine.'),
(1003, 8, ${admin_id}, 1771771670000, 1772030870000, 2, 1, true, 1, 'Office printer not printing - paper jam message', 'HP LaserJet on 3rd floor shows paper jam error but no paper stuck. Staff cannot print.'),
(1004, 9, ${admin_id}, 1771771680000, 1772030880000, 2, 1, true, 1, 'VPN connection dropping every 30 minutes', 'VPN disconnects every 30 minutes since IT department pushed latest update.'),
(1005, 10, ${admin_id}, 1771771690000, 1772030890000, 2, 1, true, 1, 'Need Adobe Acrobat Pro installed for contract review', 'Need Adobe Acrobat Pro DC for contract review. Currently using Reader only.')
ON CONFLICT (workorderid) DO NOTHING;
" 2>&1 | grep -v '^$' >> "$SETUP_LOG" || true

    # Insert workorder states (statusid=2=Open; priorityid: 4=High,3=Medium,1=Low)
    sdp_db_exec "
INSERT INTO workorderstates (workorderid, statusid, priorityid, categoryid) VALUES
(1001, 2, 4, 2),
(1002, 2, 3, 3),
(1003, 2, 4, 2),
(1004, 2, 4, 10),
(1005, 2, 1, 3)
ON CONFLICT (workorderid) DO NOTHING;
" 2>&1 | grep -v '^$' >> "$SETUP_LOG" || true

    # Insert descriptions in workordertodescription
    sdp_db_exec "
INSERT INTO workordertodescription (workorderid, fulldescription) VALUES
(1001, 'Keys are unresponsive after recent Windows update. All keys affected.'),
(1002, 'SMTP connection errors when sending emails. Receiving works fine.'),
(1003, 'HP LaserJet on 3rd floor shows paper jam error but no paper stuck.'),
(1004, 'VPN disconnects every 30 minutes since IT pushed latest update.'),
(1005, 'Need Adobe Acrobat Pro DC for contract review. Currently Reader only.')
ON CONFLICT (workorderid) DO NOTHING;
" 2>&1 | grep -v '^$' >> "$SETUP_LOG" || true

    local final_count
    final_count=$(sdp_db_exec "SELECT COUNT(*) FROM workorder WHERE workorderid IN (1001,1002,1003,1004,1005);" 2>/dev/null | tr -d '[:space:]')
    log "Initial requests created: count=$final_count"
}

# ==============================================================================
# ensure_sdp_running: Main setup function called by pre_task hooks
# ==============================================================================
ensure_sdp_running() {
    # Check if already running
    if [ -f "$SERVICE_MARKER" ] && [ "$(cat "$SERVICE_MARKER" 2>/dev/null)" = "OK" ]; then
        local http
        http=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 \
            "${SDP_BASE_URL}/ManageEngine/Login.do" 2>/dev/null || echo "000")
        if [ "$http" = "200" ] || [ "$http" = "302" ]; then
            log "SDP already running (HTTP $http)."
            return 0
        fi
        log "SDP marker exists but not responding (HTTP $http), restarting..."
        rm -f "$SERVICE_MARKER"
    fi

    # Prevent concurrent setup (simple file-based mutex)
    local mutex_waited=0
    while [ -f "$SETUP_MUTEX" ]; do
        local mpid
        mpid=$(cat "$SETUP_MUTEX" 2>/dev/null)
        if ! kill -0 "$mpid" 2>/dev/null; then
            rm -f "$SETUP_MUTEX"
            break
        fi
        sleep 15
        mutex_waited=$((mutex_waited + 15))
        if [ $mutex_waited -ge 3600 ]; then
            log "Mutex timeout, proceeding anyway"
            break
        fi
        log "Waiting for other setup process ($mpid)..."
    done

    # Check again after waiting
    if [ -f "$SERVICE_MARKER" ] && [ "$(cat "$SERVICE_MARKER" 2>/dev/null)" = "OK" ]; then
        log "SDP ready (set by other process)."
        return 0
    fi

    echo $$ > "$SETUP_MUTEX"
    log "=== ensure_sdp_running starting (PID $$) ==="

    # 1. Wait for installation
    wait_for_sdp_install 3000 || { rm -f "$SETUP_MUTEX"; exit 1; }

    if [ ! -d "$SDP_HOME/bin" ]; then
        log "ERROR: $SDP_HOME/bin not found"
        rm -f "$SETUP_MUTEX"
        exit 1
    fi

    # 2. Fix PostgreSQL permissions (CRITICAL for first run)
    fix_pgsql_permissions

    # 3. Start SDP
    start_sdp

    # 4. Wait for web UI (SDP takes 2-10 min to start)
    if ! wait_for_sdp_https 600; then
        log "SDP web UI not responding. Checking logs..."
        tail -30 /tmp/sdp_start.log >> "$SETUP_LOG" 2>&1 || true
        rm -f "$SETUP_MUTEX"
        exit 1
    fi

    # 5. Clear mandatory password change (after DB is initialized)
    sleep 10
    clear_mandatory_password_change

    # 6. Get API key
    log "Getting API key..."
    local api_key
    api_key=$(get_sdp_api_key_from_db)
    if [ -n "$api_key" ] && [ ${#api_key} -gt 20 ]; then
        echo "$api_key" > /tmp/sdp_api_key.txt
        log "DB API key: ${api_key:0:10}..."
    else
        write_python_login_script
        api_key=$(python3 /tmp/sdp_login.py 2>>"$SETUP_LOG")
        if [ -n "$api_key" ] && [ ${#api_key} -gt 10 ]; then
            echo "$api_key" > /tmp/sdp_api_key.txt
            log "Web API key: ${api_key:0:10}..."
        else
            log "WARNING: No API key - REST API calls will fail"
        fi
    fi

    # 7. Create initial sample requests
    create_initial_requests

    echo "OK" > "$SERVICE_MARKER"
    rm -f "$SETUP_MUTEX"
    log "=== SDP ready! ==="
}

# ==============================================================================
# _refresh_sdp_profile: Ensure Firefox profile exists with first-run suppression
# ==============================================================================
_refresh_sdp_profile() {
    local PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/sdp.profile"
    local FF_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
    mkdir -p "$PROFILE_DIR"

    # Ensure profiles.ini exists
    if [ ! -f "$FF_BASE/profiles.ini" ]; then
        cat > "$FF_BASE/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=sdp.profile
Locked=1

[Profile0]
Name=sdp-profile
IsRelative=1
Path=sdp.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
    fi

    # Refresh user.js with comprehensive first-run suppression
    cat > "$PROFILE_DIR/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.policy.dataSubmissionPolicyAcceptedVersion", 2);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("browser.startup.homepage", "https://localhost:8080/ManageEngine/Login.do");
user_pref("browser.startup.page", 0);
user_pref("browser.newtabpage.enabled", false);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("security.insecure_field_warning.contextual.enabled", false);
user_pref("security.certerrors.permanentOverride", true);
user_pref("security.default_personal_cert", "Ask Every Time");
user_pref("security.enterprise_roots.enabled", true);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("browser.places.importBookmarksHTML", false);
user_pref("browser.bookmarks.addedImportButton", true);
user_pref("browser.toolbars.bookmarks.visibility", "never");
USERJS

    # Fix snap Firefox data directory permissions
    local SNAP_FF_VERSION
    SNAP_FF_VERSION=$(snap list firefox 2>/dev/null | awk '/firefox/{print $3}')
    if [ -n "$SNAP_FF_VERSION" ]; then
        mkdir -p "/home/ga/snap/firefox/$SNAP_FF_VERSION"
    fi

    chown -R ga:ga /home/ga/snap/ 2>/dev/null || true
}

# ==============================================================================
# _handle_cert_warning: Detect and dismiss Firefox self-signed cert warning
# Retries up to 3 times with different xdotool strategies
# ==============================================================================
_handle_cert_warning() {
    local attempt
    for attempt in 1 2 3; do
        local title
        title=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null \
            | grep -iE "Warning.*Security|Potential.*Risk|Did Not Connect|Risk" | head -1)
        if [ -z "$title" ]; then
            return 0
        fi
        log "Cert warning detected (attempt $attempt), auto-accepting..."

        # Strategy: click "Advanced..." button then "Accept the Risk and Continue"
        su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Tab Tab Tab Tab Return" 2>/dev/null || true
        sleep 2
        su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Tab Tab Return" 2>/dev/null || true
        sleep 3

        # If still showing warning, try mouse click approach
        title=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null \
            | grep -iE "Warning.*Security|Potential.*Risk|Did Not Connect|Risk" | head -1)
        if [ -n "$title" ]; then
            log "Retrying cert acceptance with alternative approach..."
            # Click the "Advanced..." button by approximate coordinates
            su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Tab Return" 2>/dev/null || true
            sleep 2
            su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Tab Tab Tab Return" 2>/dev/null || true
            sleep 3
        fi
    done

    # Final check
    local final_title
    final_title=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null \
        | grep -iE "Warning.*Security|Potential.*Risk|Did Not Connect|Risk" | head -1)
    if [ -n "$final_title" ]; then
        log "WARNING: Could not dismiss cert warning after 3 attempts"
        return 1
    fi
    log "Cert warning accepted"
    return 0
}

# ==============================================================================
# ensure_firefox_on_sdp: Open Firefox showing SDP login page
# ==============================================================================
ensure_firefox_on_sdp() {
    local url="${1:-${SDP_BASE_URL}/ManageEngine/Login.do}"
    log "Opening Firefox on: $url"

    # Ensure profile has first-run suppression prefs before launching
    _refresh_sdp_profile

    pkill -9 -f firefox 2>/dev/null || true
    sleep 2

    local PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/sdp.profile"
    mkdir -p "$PROFILE_DIR"
    # Clear session cookies and locks to ensure fresh login page (prevents stale-session 404)
    rm -f "$PROFILE_DIR/.parentlock" "$PROFILE_DIR/lock" \
          "$PROFILE_DIR/cookies.sqlite" "$PROFILE_DIR/cookies.sqlite-shm" \
          "$PROFILE_DIR/cookies.sqlite-wal" "$PROFILE_DIR/sessionstore.jsonlz4" \
          2>/dev/null || true

    # Extract SDP self-signed cert and import into Firefox profile NSS database
    # (snap Firefox can't see system trust store, so certutil import is required)
    openssl s_client -connect "localhost:8080" -servername localhost \
        </dev/null 2>/dev/null | openssl x509 -outform PEM > /tmp/sdp_cert.pem 2>/dev/null || true
    if [ -s /tmp/sdp_cert.pem ] && command -v certutil >/dev/null 2>&1; then
        [ ! -f "$PROFILE_DIR/cert9.db" ] && certutil -N -d "sql:$PROFILE_DIR" --empty-password 2>/dev/null || true
        certutil -A -d "sql:$PROFILE_DIR" -n "ServiceDeskPlus" -t "CT,," -i /tmp/sdp_cert.pem 2>/dev/null || true
        log "SDP cert imported into Firefox profile via certutil"
    fi

    chown -R ga:ga /home/ga/snap/ 2>/dev/null || true

    su - ga -c "
        rm -f \"$PROFILE_DIR/.parentlock\" \"$PROFILE_DIR/lock\" 2>/dev/null || true
        export DISPLAY=:1
        export XAUTHORITY=/run/user/1000/gdm/Xauthority
        setsid firefox --new-instance \
            -profile \"$PROFILE_DIR\" \
            '$url' > /tmp/firefox_sdp.log 2>&1 &
    "
    sleep 10

    # Maximize Firefox so button positions are predictable at 1920x1080
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1

    # Close any Library/bookmarks dialog window
    local lib_win
    lib_win=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null \
        | grep -i "Library" | head -1)
    if [ -n "$lib_win" ]; then
        log "Closing Library dialog..."
        local lib_wid
        lib_wid=$(echo "$lib_win" | awk '{print $1}')
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -i -c "$lib_wid" 2>/dev/null || true
        sleep 1
    fi

    # Accept cert warnings: loop through tabs clicking Advanced then Accept
    # Coordinates from visual grounding at 1920x1080 maximized:
    #   "Advanced..." initial: (1319, 752), "Accept the Risk": (1253, 504) after expand
    local _cert_round
    for _cert_round in 1 2 3; do
        local _cw
        _cw=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null \
            | grep -i "Warning.*Security\|Potential.*Risk" | head -1)
        [ -z "$_cw" ] && break
        log "Cert warning (round $_cert_round), accepting..."
        # Click "Advanced..." button
        su - ga -c "export DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove 1319 752 click 1" 2>/dev/null || true
        sleep 2
        # Click "Accept the Risk and Continue" button (position after Advanced expands)
        su - ga -c "export DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove 1253 504 click 1" 2>/dev/null || true
        sleep 3
        # Switch to next tab in case another tab has cert warning
        su - ga -c "export DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool key ctrl+Tab" 2>/dev/null || true
        sleep 1
    done

    # Navigate to SDP URL if not already showing it
    local win_title
    win_title=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null \
        | grep -i "firefox\|mozilla" | head -1 || true)
    if [ -n "$win_title" ] && ! echo "$win_title" | grep -qiE "ManageEngine|ServiceDesk|Login"; then
        log "Navigating to $url..."
        su - ga -c "export DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool key ctrl+l; sleep 0.5; xdotool type --clearmodifiers '$url'; sleep 0.3; xdotool key Return" 2>/dev/null || true
        sleep 5
        # Accept cert warning one more time if needed
        local _cw2
        _cw2=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null \
            | grep -i "Warning.*Security\|Potential.*Risk" | head -1)
        if [ -n "$_cw2" ]; then
            log "Cert warning after navigate, accepting..."
            su - ga -c "export DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove 1319 752 click 1" 2>/dev/null || true
            sleep 2
            su - ga -c "export DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove 1253 504 click 1" 2>/dev/null || true
            sleep 3
        fi
    fi

    log "Firefox launched."
}

# ==============================================================================
# take_screenshot: Capture VM screenshot
# ==============================================================================
take_screenshot() {
    local outfile="${1:-/tmp/sdp_screen.png}"
    su - ga -c "
        export DISPLAY=:1
        export XAUTHORITY=/run/user/1000/gdm/Xauthority
        scrot '$outfile' 2>/dev/null || import -window root '$outfile' 2>/dev/null
    " 2>/dev/null || true
    ls -la "$outfile" 2>/dev/null || echo "screenshot: $outfile not created"
}

log "task_utils.sh loaded"

# ==============================================================================
# find_request_id: Find a request ID by subject keyword (case-insensitive)
# ==============================================================================
find_request_id() {
    local keyword="$1"
    sdp_db_exec "SELECT wo.workorderid FROM workorder wo WHERE LOWER(wo.title) LIKE LOWER('%${keyword}%') ORDER BY wo.workorderid LIMIT 1;" 2>/dev/null | tr -d '[:space:]'
}
