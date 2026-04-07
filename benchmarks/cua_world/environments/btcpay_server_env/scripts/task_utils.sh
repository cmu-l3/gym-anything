#!/bin/bash
# Shared utilities for BTCPay Server tasks

# Set X11 environment for root running GUI tools on ga's display
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Load environment variables
load_btcpay_env() {
    if [ -f /home/ga/btcpay/.env ]; then
        source /home/ga/btcpay/.env
    else
        echo "ERROR: /home/ga/btcpay/.env not found" >&2
        return 1
    fi
}

# BTCPay API call helper
btcpay_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    load_btcpay_env

    if [ -n "$data" ]; then
        curl -s -X "$method" "${BTCPAY_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -H "Authorization: token ${API_KEY}" \
            -d "$data" 2>/dev/null
    else
        curl -s -X "$method" "${BTCPAY_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -H "Authorization: token ${API_KEY}" 2>/dev/null
    fi
}

# Get invoice count for store
get_invoice_count() {
    load_btcpay_env
    local response
    response=$(btcpay_api GET "/api/v1/stores/${STORE_ID}/invoices")
    echo "$response" | jq 'length' 2>/dev/null || echo "0"
}

# Get payment request count
get_payment_request_count() {
    load_btcpay_env
    local response
    response=$(btcpay_api GET "/api/v1/stores/${STORE_ID}/payment-requests")
    echo "$response" | jq 'length' 2>/dev/null || echo "0"
}

# Get apps count
get_apps_count() {
    load_btcpay_env
    local response
    response=$(btcpay_api GET "/api/v1/stores/${STORE_ID}/apps")
    echo "$response" | jq 'length' 2>/dev/null || echo "0"
}

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    scrot "$path" 2>/dev/null || \
        import -window root "$path" 2>/dev/null || true
}

# Wait for Firefox window to appear
wait_for_firefox() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        WID=$(wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "Firefox window found: $WID" >&2
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "WARNING: Firefox window not found after ${timeout}s" >&2
    return 1
}

# Focus and maximize Firefox
focus_firefox() {
    local WID
    WID=$(wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        wmctrl -ia "$WID"
        sleep 0.5
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
        return 0
    fi
    return 1
}

# Navigate Firefox to a URL
navigate_to() {
    local url="$1"
    xdotool key ctrl+l
    sleep 0.5
    xdotool type --clearmodifiers "$url"
    sleep 0.3
    xdotool key Return
    sleep 3
}

# Wait for page to finish loading (basic check via title change)
wait_for_page_load() {
    local timeout="${1:-15}"
    sleep "$timeout"
}

# Query PostgreSQL via docker exec
btcpay_db_query() {
    local query="$1"
    docker exec btcpay-postgres psql -U postgres -d btcpayserver -t -A -c "$query" 2>/dev/null
}

# Bitcoin CLI helper
bitcoin_cli() {
    docker exec btcpay-bitcoind bitcoin-cli -regtest \
        -rpcuser=btcrpc -rpcpassword=btcrpcpass -rpcport=43782 \
        "$@" 2>/dev/null
}

# Type text reliably using xdotool key (char-by-char), works with snap Firefox
xdotool_type_reliable() {
    local text="$1"
    local i=0
    while [ $i -lt ${#text} ]; do
        local char="${text:$i:1}"
        case "$char" in
            '@') xdotool key at ;;
            '.') xdotool key period ;;
            '-') xdotool key minus ;;
            '_') xdotool key underscore ;;
            '!') xdotool key exclam ;;
            '#') xdotool key numbersign ;;
            '$') xdotool key dollar ;;
            '%') xdotool key percent ;;
            '&') xdotool key ampersand ;;
            ' ') xdotool key space ;;
            '/') xdotool key slash ;;
            ':') xdotool key colon ;;
            ',') xdotool key comma ;;
            '(') xdotool key parenleft ;;
            ')') xdotool key parenright ;;
            [A-Z]) xdotool key "shift+$(echo "$char" | tr '[:upper:]' '[:lower:]')" ;;
            *) xdotool key "$char" ;;
        esac
        i=$((i + 1))
    done
}

# Login to BTCPay Server via Firefox
# Writes a temp script and runs it as user ga (snap Firefox requires the owning user)
btcpay_firefox_login() {
    load_btcpay_env

    echo "Logging into BTCPay Server via Firefox..." >&2

    # Write login script to temp file (must run as ga, not root)
    cat > /tmp/btcpay_login.sh << LOGINEOF
#!/bin/bash
export DISPLAY=:1

# Wait for the login page to fully load before interacting
# (fixes race condition where Firefox hasn't finished loading yet)
WAIT_ELAPSED=0
while [ \$WAIT_ELAPSED -lt 30 ]; do
    PTITLE=\$(xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "\$PTITLE" | grep -qi "sign in\|btcpay\|login"; then
        break
    fi
    sleep 2
    WAIT_ELAPSED=\$((WAIT_ELAPSED + 2))
done
# Extra settle time for form elements to become interactive
sleep 3

# Refresh page to get clean login form (no stale validation errors)
xdotool key F5
sleep 5

# F6 to focus page content, Tab to first form input (email)
xdotool key F6
sleep 1
xdotool key Tab
sleep 0.5

# Type email char by char with small delays
for c in a d m i n; do xdotool key \$c; sleep 0.03; done
xdotool key at; sleep 0.03
for c in n a k a m o t o; do xdotool key \$c; sleep 0.03; done
xdotool key minus; sleep 0.03
for c in e l e c t r o n i c s; do xdotool key \$c; sleep 0.03; done
xdotool key period; sleep 0.03
for c in c o m; do xdotool key \$c; sleep 0.03; done
sleep 0.3

# Tab to password field
xdotool key Tab
sleep 0.3

# Type password: BTCPay_Admin_2024!
xdotool key shift+b; sleep 0.03
xdotool key shift+t; sleep 0.03
xdotool key shift+c; sleep 0.03
xdotool key shift+p; sleep 0.03
for c in a y; do xdotool key \$c; sleep 0.03; done
xdotool key underscore; sleep 0.03
xdotool key shift+a; sleep 0.03
for c in d m i n; do xdotool key \$c; sleep 0.03; done
xdotool key underscore; sleep 0.03
for c in 2 0 2 4; do xdotool key \$c; sleep 0.03; done
xdotool key exclam; sleep 0.03
sleep 0.3

# Submit
xdotool key Return
sleep 8

# Report result
TITLE=\$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Login title: \$TITLE"
LOGINEOF

    chmod +x /tmp/btcpay_login.sh
    chown ga:ga /tmp/btcpay_login.sh

    # Run as ga user (critical: snap Firefox only accepts input from the owning user)
    su - ga -c "bash /tmp/btcpay_login.sh" 2>&1 | while read -r line; do
        echo "  $line" >&2
    done

    rm -f /tmp/btcpay_login.sh
    return 0
}

# Safe write result to file
safe_write_result() {
    local path="$1"
    local content="$2"
    local TEMP
    TEMP=$(mktemp /tmp/result.XXXXXX.json)
    echo "$content" > "$TEMP"
    rm -f "$path" 2>/dev/null || sudo rm -f "$path" 2>/dev/null || true
    cp "$TEMP" "$path" 2>/dev/null || sudo cp "$TEMP" "$path"
    chmod 666 "$path" 2>/dev/null || sudo chmod 666 "$path" 2>/dev/null || true
    rm -f "$TEMP"
}
