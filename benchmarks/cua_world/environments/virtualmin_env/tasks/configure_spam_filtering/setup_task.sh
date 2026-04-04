#!/bin/bash
set -e
echo "=== Setting up configure_spam_filtering task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Ensure SpamAssassin is installed
# ---------------------------------------------------------------
echo "--- Ensuring SpamAssassin is installed ---"
if ! which spamassassin >/dev/null; then
    apt-get update && apt-get install -y spamassassin spamc procmail
fi
systemctl enable spamassassin 2>/dev/null || true
systemctl start spamassassin 2>/dev/null || true

# ---------------------------------------------------------------
# 2. Ensure greenfield.test exists
# ---------------------------------------------------------------
if ! virtualmin_domain_exists "greenfield.test"; then
    echo "Creating greenfield.test..."
    virtualmin create-domain --domain greenfield.test --pass "GreenField123!" --unix --dir --webmin --web --dns --mail 2>/dev/null
fi

# ---------------------------------------------------------------
# 3. Reset spam state for greenfield.test
# ---------------------------------------------------------------
echo "--- Resetting spam state for greenfield.test ---"

# Disable spam filtering initially (task requirement: enable it)
virtualmin disable-feature --domain greenfield.test --spam 2>/dev/null || true

# Clean up configuration files to ensure fresh start
GREENFIELD_HOME=$(grep "^greenfield:" /etc/passwd 2>/dev/null | cut -d: -f6)
if [ -z "$GREENFIELD_HOME" ]; then GREENFIELD_HOME="/home/greenfield"; fi

rm -f "${GREENFIELD_HOME}/.spamassassin/user_prefs" 2>/dev/null || true
rm -f "${GREENFIELD_HOME}/.spamassassin/local.cf" 2>/dev/null || true
# Reset procmailrc to basic state
if [ -f "${GREENFIELD_HOME}/.procmailrc" ]; then
    grep -v "spam" "${GREENFIELD_HOME}/.procmailrc" > "${GREENFIELD_HOME}/.procmailrc.tmp" 2>/dev/null || true
    mv "${GREENFIELD_HOME}/.procmailrc.tmp" "${GREENFIELD_HOME}/.procmailrc"
    chown greenfield:greenfield "${GREENFIELD_HOME}/.procmailrc"
fi

# Record initial state hashes for anti-gaming
echo "Recording initial state..."
md5sum "${GREENFIELD_HOME}/.procmailrc" 2>/dev/null > /tmp/initial_procmail_hash.txt || echo "none" > /tmp/initial_procmail_hash.txt
virtualmin list-domains --domain greenfield.test --multiline > /tmp/initial_domain_config.txt 2>/dev/null || true

# ---------------------------------------------------------------
# 4. Prepare UI
# ---------------------------------------------------------------
echo "--- Ensuring Virtualmin is ready in Firefox ---"
ensure_virtualmin_ready

# Navigate to the domain summary page for greenfield.test
DOMAIN_ID=$(get_domain_id "greenfield.test")
navigate_to "https://localhost:10000/virtual-server/summary_domain.cgi?dom=${DOMAIN_ID}"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="