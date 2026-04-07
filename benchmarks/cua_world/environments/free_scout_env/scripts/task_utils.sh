#!/bin/bash
# Shared utilities for FreeScout tasks
# Source this from setup_task.sh and export_result.sh

# ===== Auto-check: wait for FreeScout web service on source =====
# This ensures Docker containers are ready after cache restore
echo "Checking FreeScout web service readiness..."
for _fs_check_i in $(seq 1 60); do
    _fs_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
    if [ "$_fs_code" = "200" ] || [ "$_fs_code" = "302" ]; then
        echo "FreeScout web service is ready"
        break
    fi
    sleep 2
done

# ===== Database Query Helper =====
fs_query() {
    local query="$1"
    local result
    result=$(docker exec freescout-db mysql -u freescout -pfreescout123 freescout -N -e "$query" 2>/dev/null)
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "" >&2
        return 1
    fi
    echo "$result"
    return 0
}

# ===== Count Helpers =====
get_mailbox_count() {
    fs_query "SELECT COUNT(*) FROM mailboxes" 2>/dev/null || echo "0"
}

get_conversation_count() {
    fs_query "SELECT COUNT(*) FROM conversations" 2>/dev/null || echo "0"
}

get_customer_count() {
    fs_query "SELECT COUNT(*) FROM customers" 2>/dev/null || echo "0"
}

get_user_count() {
    fs_query "SELECT COUNT(*) FROM users" 2>/dev/null || echo "0"
}

get_thread_count() {
    fs_query "SELECT COUNT(*) FROM threads" 2>/dev/null || echo "0"
}

# ===== Search Helpers =====
find_mailbox_by_name() {
    local name="$1"
    # Try exact match first
    local result
    result=$(fs_query "SELECT id, name, email FROM mailboxes WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name')) ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    # Try partial match
    result=$(fs_query "SELECT id, name, email FROM mailboxes WHERE LOWER(name) LIKE '%$(echo "$name" | tr '[:upper:]' '[:lower:]')%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    echo ""
    return 1
}

find_conversation_by_subject() {
    local subject="$1"
    local result
    result=$(fs_query "SELECT id, number, subject, status, mailbox_id, user_id, customer_id FROM conversations WHERE LOWER(TRIM(subject)) = LOWER(TRIM('$subject')) ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    result=$(fs_query "SELECT id, number, subject, status, mailbox_id, user_id, customer_id FROM conversations WHERE LOWER(subject) LIKE '%$(echo "$subject" | tr '[:upper:]' '[:lower:]')%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    echo ""
    return 1
}

find_customer_by_email() {
    local email="$1"
    local result
    result=$(fs_query "SELECT c.id, c.first_name, c.last_name FROM customers c JOIN emails e ON c.id = e.customer_id WHERE LOWER(TRIM(e.email)) = LOWER(TRIM('$email')) ORDER BY c.id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    echo ""
    return 1
}

find_customer_by_name() {
    local first_name="$1"
    local last_name="$2"
    local result
    result=$(fs_query "SELECT id, first_name, last_name FROM customers WHERE LOWER(TRIM(first_name)) = LOWER(TRIM('$first_name')) AND LOWER(TRIM(last_name)) = LOWER(TRIM('$last_name')) ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    result=$(fs_query "SELECT id, first_name, last_name FROM customers WHERE LOWER(first_name) LIKE '%$(echo "$first_name" | tr '[:upper:]' '[:lower:]')%' AND LOWER(last_name) LIKE '%$(echo "$last_name" | tr '[:upper:]' '[:lower:]')%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    echo ""
    return 1
}

find_user_by_email() {
    local email="$1"
    local result
    result=$(fs_query "SELECT id, first_name, last_name, email, role FROM users WHERE LOWER(TRIM(email)) = LOWER(TRIM('$email')) ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    echo ""
    return 1
}

find_user_by_name() {
    local first_name="$1"
    local last_name="$2"
    local result
    result=$(fs_query "SELECT id, first_name, last_name, email, role FROM users WHERE LOWER(TRIM(first_name)) = LOWER(TRIM('$first_name')) AND LOWER(TRIM(last_name)) = LOWER(TRIM('$last_name')) ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    echo ""
    return 1
}

# ===== Screenshot Helper =====
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# ===== Web Service Wait =====
wait_for_freescout() {
    local timeout=${1:-120}
    local elapsed=0
    echo "Waiting for FreeScout web service..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "FreeScout is ready (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: FreeScout not ready after ${timeout}s"
    return 1
}

# ===== Firefox Launch with Wait =====
restart_firefox() {
    local url="${1:-http://localhost:8080}"

    # Wait for FreeScout web service before launching Firefox
    wait_for_freescout 120 || echo "WARNING: FreeScout may not be ready"

    # Kill any stale Firefox
    pkill -9 -f firefox 2>/dev/null || true
    sleep 3

    su - ga -c "DISPLAY=:1 firefox '$url' > /tmp/firefox.log 2>&1 &"

    # Wait for Firefox window
    wait_for_window "firefox\|mozilla\|freescout" 30

    # Maximize Firefox
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
}

# ===== Firefox Helpers =====
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

focus_firefox() {
    DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "Mozilla" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "FreeScout" 2>/dev/null || true
    sleep 1
}

navigate_to_url() {
    local url="$1"
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 20 "$url"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 3
}

ensure_logged_in() {
    # Check if we're on a login page and log in if needed
    local current_url
    current_url=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "$current_url" | grep -qi "login"; then
        echo "Login page detected, logging in..."
        navigate_to_url "http://localhost:8080/login"
        sleep 2
    fi
}

# ===== Result File Helper =====
safe_write_result() {
    local source="$1"
    local dest="$2"
    rm -f "$dest" 2>/dev/null || sudo rm -f "$dest" 2>/dev/null || true
    cp "$source" "$dest" 2>/dev/null || sudo cp "$source" "$dest"
    chmod 666 "$dest" 2>/dev/null || sudo chmod 666 "$dest" 2>/dev/null || true
}

# ===== Nonce Helpers =====
generate_result_nonce() {
    local nonce
    nonce=$(head -c 16 /dev/urandom | xxd -p)
    echo "$nonce" > /tmp/result_nonce
    chmod 666 /tmp/result_nonce 2>/dev/null || true
    echo "$nonce"
}

get_result_nonce() {
    cat /tmp/result_nonce 2>/dev/null || echo ""
}

# ===== FreeScout ORM Helper =====
# Run PHP code via artisan tinker for proper ORM operations
fs_tinker() {
    local php_code="$1"
    echo "$php_code" | docker exec -i freescout-app php /www/html/artisan tinker 2>&1
}

# Create a mailbox via ORM (triggers folder creation)
ensure_mailbox_exists() {
    local name="${1:-Support}"
    local email="${2:-support@helpdesk.local}"
    local existing_id
    existing_id=$(fs_query "SELECT id FROM mailboxes WHERE email = '$email' LIMIT 1" 2>/dev/null)
    if [ -n "$existing_id" ]; then
        echo "$existing_id"
        return 0
    fi
    # Create via tinker to trigger folder creation
    local result
    result=$(fs_tinker "
\$m = new \\App\\Mailbox();
\$m->name = '$name';
\$m->email = '$email';
\$m->save();
echo 'MAILBOX_ID:' . \$m->id;
")
    echo "$result" | grep 'MAILBOX_ID:' | sed 's/MAILBOX_ID://' | tr -cd '0-9'
}

# Create a conversation via ORM (handles folder_id and number automatically)
create_conversation_via_orm() {
    local subject="$1"
    local mailbox_id="$2"
    local customer_email="${3:-}"
    local customer_id="${4:-}"
    local body="${5:-}"

    local customer_part=""
    if [ -n "$customer_email" ]; then
        customer_part="\$conv->customer_email = '$customer_email';"
    fi
    if [ -n "$customer_id" ]; then
        customer_part="$customer_part
\$conv->customer_id = $customer_id;"
    fi

    local thread_part=""
    if [ -n "$body" ]; then
        # Escape single quotes in body
        local escaped_body
        escaped_body=$(echo "$body" | sed "s/'/\\\\'/g")
        thread_part="
\$thread = new \\App\\Thread();
\$thread->conversation_id = \$conv->id;
\$thread->type = 1;
\$thread->status = 1;
\$thread->state = 3;
\$thread->body = '$escaped_body';
\$thread->source_type = 1;
\$thread->source_via = 2;
\$thread->first = true;
\$thread->customer_id = \$conv->customer_id;
\$thread->created_by_customer_id = \$conv->customer_id;
\$thread->save();
\$conv->threads_count = 1;
\$conv->preview = substr('$escaped_body', 0, 255);
\$conv->last_reply_at = now();
\$conv->last_reply_from = 2;
\$conv->save();
"
    fi

    local result
    result=$(fs_tinker "
\$conv = new \\App\\Conversation();
\$conv->type = 1;
\$conv->subject = '$subject';
\$conv->mailbox_id = $mailbox_id;
\$conv->status = 1;
\$conv->state = 2;
\$conv->source_type = 1;
\$conv->source_via = 2;
\$conv->preview = '';
$customer_part
\$conv->save();
// Set folder_id to Unassigned (type 1) folder for this mailbox
\$folder = \\App\\Folder::where('mailbox_id', $mailbox_id)->where('type', 1)->first();
if (\$folder) {
    \$conv->folder_id = \$folder->id;
    \$conv->save();
    \$folder->updateCounters();
}
echo 'CONV_ID:' . \$conv->id;
$thread_part
")
    echo "$result" | grep 'CONV_ID:' | sed 's/CONV_ID://' | tr -cd '0-9'
}
