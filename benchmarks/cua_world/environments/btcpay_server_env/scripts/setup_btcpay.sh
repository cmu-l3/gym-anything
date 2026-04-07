#!/bin/bash
# NOTE: Do NOT use set -e here. Polling functions and curl return non-zero
# on timeout/failure, which would kill the entire setup script prematurely.

echo "=== Setting up BTCPay Server ==="

BTCPAY_URL="http://localhost"
ADMIN_EMAIL="admin@nakamoto-electronics.com"
ADMIN_PASS="BTCPay_Admin_2024!"
STORE_NAME="Nakamoto Electronics"

# ── Service Readiness Functions ──────────────────────────────────────────────

wait_for_postgres() {
    local timeout="${1:-120}"
    local elapsed=0
    echo "Waiting for PostgreSQL..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec btcpay-postgres pg_isready -U postgres 2>/dev/null | grep -q "accepting connections"; then
            echo "PostgreSQL ready after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: PostgreSQL not ready after ${timeout}s"
    return 1
}

wait_for_bitcoind() {
    local timeout="${1:-120}"
    local elapsed=0
    echo "Waiting for Bitcoin daemon (regtest)..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec btcpay-bitcoind bitcoin-cli -regtest -rpcuser=btcrpc -rpcpassword=btcrpcpass -rpcport=43782 getblockchaininfo > /dev/null 2>&1; then
            echo "Bitcoin daemon ready after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: Bitcoin daemon not ready after ${timeout}s"
    return 1
}

wait_for_btcpay() {
    local timeout="${1:-180}"
    local elapsed=0
    echo "Waiting for BTCPay Server..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BTCPAY_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "BTCPay Server ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
        echo "  BTCPay: HTTP $HTTP_CODE (${elapsed}s elapsed)"
    done
    echo "WARNING: BTCPay Server not ready after ${timeout}s"
    return 1
}

wait_for_nbxplorer() {
    local timeout="${1:-120}"
    local elapsed=0
    echo "Waiting for NBXplorer (port 32838)..."
    while [ $elapsed -lt $timeout ]; do
        # Check if nbxplorer container is running and the port responds
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:32838/health" 2>/dev/null || echo "000")
        echo "  NBXplorer: HTTP $HTTP_CODE (${elapsed}s elapsed)"
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "401" ]; then
            echo "NBXplorer ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "WARNING: NBXplorer not ready after ${timeout}s, continuing anyway..."
    return 0
}

# ── Start Docker Compose Stack ───────────────────────────────────────────────

echo "Starting BTCPay Server stack..."
mkdir -p /home/ga/btcpay
cp /workspace/config/docker-compose.yml /home/ga/btcpay/docker-compose.yml
chown -R ga:ga /home/ga/btcpay

cd /home/ga/btcpay
docker compose pull 2>/dev/null || true
docker compose up -d

# Wait for services in order
wait_for_postgres 120
wait_for_bitcoind 120
wait_for_nbxplorer 120
wait_for_btcpay 180

# ── Mine Initial Regtest Blocks ──────────────────────────────────────────────

echo "Mining initial regtest blocks..."
# Create a descriptor wallet (BDB wallets deprecated in Bitcoin Core 29.x)
docker exec btcpay-bitcoind bitcoin-cli -regtest \
    -rpcuser=btcrpc -rpcpassword=btcrpcpass -rpcport=43782 \
    -named createwallet wallet_name="default" descriptors=true || true

docker exec btcpay-bitcoind bitcoin-cli -regtest \
    -rpcuser=btcrpc -rpcpassword=btcrpcpass -rpcport=43782 \
    -generate 110 > /dev/null 2>&1 || true

echo "Mined 110 regtest blocks"

# Wait for NBXplorer to sync the mined blocks and BTCPay chain services to be available
echo "Waiting for BTC chain services to become available in BTCPay..."
CHAIN_TIMEOUT=120
CHAIN_ELAPSED=0
while [ $CHAIN_ELAPSED -lt $CHAIN_TIMEOUT ]; do
    CHAIN_STATUS=$(curl -s "${BTCPAY_URL}/api/v1/health" 2>/dev/null | jq -r '.synchronized // false' 2>/dev/null)
    if [ "$CHAIN_STATUS" = "true" ]; then
        echo "BTCPay chain services ready after ${CHAIN_ELAPSED}s"
        break
    fi
    # Also check server info for sync status
    SERVER_STATUS=$(curl -s "${BTCPAY_URL}/api/v1/server/info" \
        -H "Authorization: Basic $(echo -n "${ADMIN_EMAIL}:${ADMIN_PASS}" | base64)" 2>/dev/null | jq -r '.synchronizedNodes // 0' 2>/dev/null)
    echo "  Chain sync: synchronized=$CHAIN_STATUS, syncedNodes=$SERVER_STATUS (${CHAIN_ELAPSED}s)"
    if [ "$SERVER_STATUS" != "0" ] && [ "$SERVER_STATUS" != "null" ] && [ -n "$SERVER_STATUS" ]; then
        echo "BTCPay has synced nodes after ${CHAIN_ELAPSED}s"
        break
    fi
    sleep 5
    CHAIN_ELAPSED=$((CHAIN_ELAPSED + 5))
done

# ── Create Admin Account via Greenfield API ──────────────────────────────────

echo "Creating admin account..."
CREATE_USER_RESPONSE=$(curl -s -X POST "${BTCPAY_URL}/api/v1/users" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"${ADMIN_EMAIL}\",
        \"password\": \"${ADMIN_PASS}\",
        \"isAdministrator\": true
    }" 2>/dev/null)

echo "User creation response: $CREATE_USER_RESPONSE"

# ── Get API Key ──────────────────────────────────────────────────────────────

echo "Generating API key..."
API_KEY_RESPONSE=$(curl -s -X POST "${BTCPAY_URL}/api/v1/api-keys" \
    -H "Content-Type: application/json" \
    -u "${ADMIN_EMAIL}:${ADMIN_PASS}" \
    -d '{
        "permissions": [
            "btcpay.server.canmodifyserversettings",
            "btcpay.store.canmodifystoresettings",
            "btcpay.store.cancreateinvoice",
            "btcpay.store.canviewinvoices",
            "btcpay.store.canmodifyinvoices",
            "btcpay.store.canviewstoresettings",
            "btcpay.store.cancreatepaymentrequest",
            "btcpay.store.canviewpaymentrequests",
            "btcpay.store.cancreatenonapprovedpullpayments",
            "btcpay.store.canmanagepullpayments",
            "btcpay.user.canviewprofile",
            "btcpay.store.canmanagepayouts"
        ]
    }' 2>/dev/null)

API_KEY=$(echo "$API_KEY_RESPONSE" | jq -r '.apiKey // empty')
if [ -z "$API_KEY" ]; then
    echo "WARNING: Failed to get API key. Response: $API_KEY_RESPONSE"
    # Try with basic auth header format
    API_KEY_RESPONSE=$(curl -s -X POST "${BTCPAY_URL}/api/v1/api-keys" \
        -H "Content-Type: application/json" \
        -H "Authorization: Basic $(echo -n "${ADMIN_EMAIL}:${ADMIN_PASS}" | base64)" \
        -d '{
            "permissions": ["unrestricted"]
        }' 2>/dev/null)
    API_KEY=$(echo "$API_KEY_RESPONSE" | jq -r '.apiKey // empty')
fi

echo "API Key: ${API_KEY}"

# Save credentials for task scripts
cat > /home/ga/btcpay/.env << EOF
BTCPAY_URL=${BTCPAY_URL}
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASS=${ADMIN_PASS}
API_KEY=${API_KEY}
EOF
chmod 600 /home/ga/btcpay/.env
chown ga:ga /home/ga/btcpay/.env

# ── Create Store ─────────────────────────────────────────────────────────────

echo "Creating store..."
STORE_RESPONSE=$(curl -s -X POST "${BTCPAY_URL}/api/v1/stores" \
    -H "Content-Type: application/json" \
    -H "Authorization: token ${API_KEY}" \
    -d "{
        \"name\": \"${STORE_NAME}\",
        \"defaultCurrency\": \"USD\",
        \"speedPolicy\": \"MediumSpeed\"
    }" 2>/dev/null)

STORE_ID=$(echo "$STORE_RESPONSE" | jq -r '.id // empty')
echo "Store ID: ${STORE_ID}"

if [ -z "$STORE_ID" ]; then
    echo "WARNING: Failed to create store. Response: $STORE_RESPONSE"
fi

# Save store ID
echo "STORE_ID=${STORE_ID}" >> /home/ga/btcpay/.env

# ── Generate Hot Wallet ──────────────────────────────────────────────────────

echo "Generating hot wallet for store..."
WALLET_RETRIES=5
WALLET_OK=0
for i in $(seq 1 $WALLET_RETRIES); do
    WALLET_RESPONSE=$(curl -s -X POST "${BTCPAY_URL}/api/v1/stores/${STORE_ID}/payment-methods/onchain/BTC/generate" \
        -H "Content-Type: application/json" \
        -H "Authorization: token ${API_KEY}" \
        -d '{
            "savePrivateKeys": true,
            "importKeysToRPC": false,
            "wordCount": 12,
            "scriptPubKeyType": "Segwit"
        }' 2>/dev/null)

    WALLET_DERIV=$(echo "$WALLET_RESPONSE" | jq -r '.config.accountDerivation // .derivationScheme // empty' 2>/dev/null)
    if [ -n "$WALLET_DERIV" ]; then
        echo "Hot wallet created: $WALLET_DERIV"
        WALLET_OK=1
        break
    fi
    echo "  Wallet attempt $i failed: $(echo "$WALLET_RESPONSE" | jq -r '.message // "unknown"' 2>/dev/null)"
    sleep 10
done

if [ "$WALLET_OK" = "0" ]; then
    echo "WARNING: Could not create hot wallet after $WALLET_RETRIES attempts"
    echo "Full response: $WALLET_RESPONSE"
fi

# ── Seed Invoice Data ────────────────────────────────────────────────────────

echo "Seeding invoice data from real product catalog..."
if [ -f /workspace/data/seed_data.json ] && [ -n "$STORE_ID" ] && [ -n "$API_KEY" ]; then
    INVOICE_COUNT=$(jq '.invoices | length' /workspace/data/seed_data.json)
    echo "Creating ${INVOICE_COUNT} invoices..."

    for i in $(seq 0 $((INVOICE_COUNT - 1))); do
        AMOUNT=$(jq -r ".invoices[$i].amount" /workspace/data/seed_data.json)
        CURRENCY=$(jq -r ".invoices[$i].currency" /workspace/data/seed_data.json)
        ORDER_ID=$(jq -r ".invoices[$i].metadata.orderId" /workspace/data/seed_data.json)
        ITEM_DESC=$(jq -r ".invoices[$i].metadata.itemDesc" /workspace/data/seed_data.json)
        BUYER_NAME=$(jq -r ".invoices[$i].metadata.buyerName" /workspace/data/seed_data.json)
        BUYER_EMAIL=$(jq -r ".invoices[$i].metadata.buyerEmail" /workspace/data/seed_data.json)

        INV_RESPONSE=$(curl -s -X POST "${BTCPAY_URL}/api/v1/stores/${STORE_ID}/invoices" \
            -H "Content-Type: application/json" \
            -H "Authorization: token ${API_KEY}" \
            -d "{
                \"amount\": \"${AMOUNT}\",
                \"currency\": \"${CURRENCY}\",
                \"metadata\": {
                    \"orderId\": \"${ORDER_ID}\",
                    \"itemDesc\": \"${ITEM_DESC}\",
                    \"buyerName\": \"${BUYER_NAME}\",
                    \"buyerEmail\": \"${BUYER_EMAIL}\"
                }
            }" 2>/dev/null)

        INV_ID=$(echo "$INV_RESPONSE" | jq -r '.id // empty')
        echo "  Invoice ${ORDER_ID}: ${INV_ID:-FAILED}"
    done

    # Seed payment requests
    PR_COUNT=$(jq '.payment_requests | length' /workspace/data/seed_data.json)
    echo "Creating ${PR_COUNT} payment requests..."

    for i in $(seq 0 $((PR_COUNT - 1))); do
        PR_TITLE=$(jq -r ".payment_requests[$i].title" /workspace/data/seed_data.json)
        PR_AMOUNT=$(jq -r ".payment_requests[$i].amount" /workspace/data/seed_data.json)
        PR_CURRENCY=$(jq -r ".payment_requests[$i].currency" /workspace/data/seed_data.json)
        PR_DESC=$(jq -r ".payment_requests[$i].description" /workspace/data/seed_data.json)

        PR_RESPONSE=$(curl -s -X POST "${BTCPAY_URL}/api/v1/stores/${STORE_ID}/payment-requests" \
            -H "Content-Type: application/json" \
            -H "Authorization: token ${API_KEY}" \
            -d "{
                \"title\": \"${PR_TITLE}\",
                \"amount\": \"${PR_AMOUNT}\",
                \"currency\": \"${PR_CURRENCY}\",
                \"description\": \"${PR_DESC}\"
            }" 2>/dev/null)

        PR_ID=$(echo "$PR_RESPONSE" | jq -r '.id // empty')
        echo "  Payment Request '${PR_TITLE}': ${PR_ID:-FAILED}"
    done
else
    echo "WARNING: Could not seed data (missing seed_data.json, STORE_ID, or API_KEY)"
fi

# ── Configure Firefox ────────────────────────────────────────────────────────

echo "Configuring Firefox profile..."
FIREFOX_DIR="/home/ga/.mozilla/firefox"
PROFILE_DIR="${FIREFOX_DIR}/default-release"
mkdir -p "$PROFILE_DIR"

cat > "${FIREFOX_DIR}/profiles.ini" << 'EOF'
[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

cat > "${PROFILE_DIR}/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("app.update.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.startup.homepage", "http://localhost/");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.page", 1);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("privacy.trackingprotection.enabled", false);
user_pref("browser.contentblocking.category", "custom");
USERJS

# Handle snap Firefox profile path
if command -v snap 2>/dev/null && snap list firefox 2>/dev/null; then
    SNAP_FIREFOX_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
    mkdir -p "${SNAP_FIREFOX_DIR}/default-release"
    cp "${FIREFOX_DIR}/profiles.ini" "${SNAP_FIREFOX_DIR}/profiles.ini"
    cp "${PROFILE_DIR}/user.js" "${SNAP_FIREFOX_DIR}/default-release/user.js"
    chown -R ga:ga "/home/ga/snap"
fi

chown -R ga:ga "$FIREFOX_DIR"

# Create desktop shortcut
cat > /home/ga/Desktop/BTCPayServer.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=BTCPay Server
Comment=Open BTCPay Server in Firefox
Exec=firefox http://localhost/
Icon=firefox
Terminal=false
Categories=Network;WebBrowser;
EOF
chmod +x /home/ga/Desktop/BTCPayServer.desktop
chown ga:ga /home/ga/Desktop/BTCPayServer.desktop

# ── Launch Firefox ───────────────────────────────────────────────────────────

echo "Launching Firefox with BTCPay Server..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_btcpay.log 2>&1 &"

# Wait for Firefox window
echo "Waiting for Firefox window..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Firefox window detected after ${ELAPSED}s: $WID"
        DISPLAY=:1 wmctrl -ia "$WID"
        sleep 1
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: Firefox window not detected after ${TIMEOUT}s"
fi

# Wait for BTCPay login page to fully load in Firefox
echo "Waiting for BTCPay login page to load..."
LOGIN_TIMEOUT=30
LOGIN_ELAPSED=0
while [ $LOGIN_ELAPSED -lt $LOGIN_TIMEOUT ]; do
    PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "$PAGE_TITLE" | grep -qi "sign in\|btcpay\|login"; then
        echo "Login page loaded after ${LOGIN_ELAPSED}s (title: $PAGE_TITLE)"
        break
    fi
    sleep 2
    LOGIN_ELAPSED=$((LOGIN_ELAPSED + 2))
    echo "  Waiting for page... (${LOGIN_ELAPSED}s, title: $PAGE_TITLE)"
done
# Extra settle time for the form to be interactive
sleep 3

# ── Login to BTCPay via Firefox ──────────────────────────────────────────────

echo "Logging into BTCPay Server via Firefox..."
source /workspace/scripts/task_utils.sh
load_btcpay_env

# Login must run as ga user (snap Firefox only accepts input from owning user)
btcpay_firefox_login

# Take verification screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/setup_verification.png 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root /tmp/setup_verification.png 2>/dev/null || true

echo "=== BTCPay Server setup complete ==="
echo "Access URL: ${BTCPAY_URL}"
echo "Admin: ${ADMIN_EMAIL} / ${ADMIN_PASS}"
echo "Store: ${STORE_NAME} (ID: ${STORE_ID})"
echo "API Key: ${API_KEY}"
