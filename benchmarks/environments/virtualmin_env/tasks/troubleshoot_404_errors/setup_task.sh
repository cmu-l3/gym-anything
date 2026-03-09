#!/bin/bash
set -e
echo "=== Setting up task: troubleshoot_404_errors@1 ==="

source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Configuration
# ---------------------------------------------------------------
DOMAIN="globalshop.test"
USER="globalshop"
ACCESS_LOG="/var/log/virtualmin/${DOMAIN}_access_log"

# Define the "secret" missing file. 
# This is what the agent must find in the logs.
MISSING_DIR="assets/seasonal"
MISSING_FILE="autumn_glory_2025.jpg"
MISSING_REL_PATH="${MISSING_DIR}/${MISSING_FILE}"
FULL_WEB_ROOT="/home/${USER}/public_html"
EXPECTED_PATH="${FULL_WEB_ROOT}/${MISSING_REL_PATH}"

# Save secret to a file for export_result.sh to read later
cat > /tmp/task_target_info.json << EOF
{
    "domain": "$DOMAIN",
    "expected_path": "$EXPECTED_PATH",
    "rel_path": "$MISSING_REL_PATH",
    "filename": "$MISSING_FILE"
}
EOF
chmod 644 /tmp/task_target_info.json

# Record start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 2. Ensure Domain Exists
# ---------------------------------------------------------------
if ! virtualmin_domain_exists "$DOMAIN"; then
    echo "Creating domain $DOMAIN..."
    # Create with basic features
    virtualmin create-domain \
        --domain "$DOMAIN" \
        --pass "GlobalShop123!" \
        --unix --dir --web --dns --mysql \
        2>&1 | tail -5
else
    echo "Domain $DOMAIN already exists."
fi

# Ensure web root exists
mkdir -p "$FULL_WEB_ROOT"

# Ensure the missing file does NOT exist (in case of retry)
rm -f "$EXPECTED_PATH"
# Remove parent dir to force agent to create it? 
# Let's remove the specific subdir to test if they create the structure
rm -rf "${FULL_WEB_ROOT}/${MISSING_DIR}"

# ---------------------------------------------------------------
# 3. Inject Log Data
# ---------------------------------------------------------------
echo "--- Injecting log entries into $ACCESS_LOG ---"

# Ensure log file exists and is empty/clean for the scenario
: > "$ACCESS_LOG"
chmod 644 "$ACCESS_LOG"

# Helpers for log generation
TODAY=$(date +%d/%b/%Y)
HH=$(date +%H)
rand_ip() { echo "$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255))"; }

UA_CHROME="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
UA_BOT="Googlebot/2.1 (+http://www.google.com/bot.html)"

log_200() {
    echo "$(rand_ip) - - [${TODAY}:${HH}:$((RANDOM%60)):$((RANDOM%60)) +0000] \"GET $1 HTTP/1.1\" 200 $((RANDOM%5000 + 500)) \"$2\" \"$UA_CHROME\"" >> "$ACCESS_LOG"
}

log_404() {
    echo "$(rand_ip) - - [${TODAY}:${HH}:$((RANDOM%60)):$((RANDOM%60)) +0000] \"GET $1 HTTP/1.1\" 404 196 \"$2\" \"$UA_CHROME\"" >> "$ACCESS_LOG"
}

# Generate Noise
log_200 "/index.html" "-"
log_200 "/css/styles.css" "http://${DOMAIN}/index.html"
log_200 "/js/app.js" "http://${DOMAIN}/index.html"
log_200 "/images/logo.png" "http://${DOMAIN}/index.html"

# Generate the SIGNAL (The 404s)
# Valid referer to make it look real
REFERER="http://${DOMAIN}/promo/fall-sale.html"

log_404 "/${MISSING_REL_PATH}" "$REFERER"
log_200 "/index.html" "-"
log_404 "/${MISSING_REL_PATH}" "$REFERER"
log_200 "/css/main.css" "http://${DOMAIN}/"
log_404 "/${MISSING_REL_PATH}" "$REFERER"
log_404 "/${MISSING_REL_PATH}" "$REFERER"

# More noise
log_200 "/favicon.ico" "-"

echo "Logs injected."

# ---------------------------------------------------------------
# 4. GUI Setup
# ---------------------------------------------------------------
ensure_virtualmin_ready

# Navigate to the specific domain's dashboard to save time
DOM_ID=$(get_domain_id "$DOMAIN")
if [ -n "$DOM_ID" ]; then
    navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi?dom=${DOM_ID}"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="