#!/bin/bash
set -e
echo "=== Setting up configure_email_autoresponder task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure acmecorp.test domain exists
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "ERROR: acmecorp.test domain does not exist!"
    # Fallback creation just in case environment is raw
    virtualmin create-domain --domain acmecorp.test --pass "AcmeCorp123!" --unix --dir --webmin --web --dns --mail --mysql
fi

# Create user sarah if she doesn't exist
if ! virtualmin list-users --domain acmecorp.test 2>/dev/null | grep -q "^sarah"; then
    echo "Creating user sarah@acmecorp.test..."
    virtualmin create-user \
        --domain acmecorp.test \
        --user sarah \
        --pass "SarahPass123!" \
        --real "Sarah Chen" \
        --quota 500 \
        --mail-quota 200 2>&1 || echo "WARNING: create-user returned non-zero"
    sleep 3
else
    echo "User sarah already exists"
    # Ensure autoresponder is OFF (reset state)
    virtualmin modify-user \
        --domain acmecorp.test \
        --user sarah \
        --no-autoresponder 2>/dev/null || true
fi

# Create user david if he doesn't exist (alternate contact)
if ! virtualmin list-users --domain acmecorp.test 2>/dev/null | grep -q "^david"; then
    echo "Creating user david@acmecorp.test..."
    virtualmin create-user \
        --domain acmecorp.test \
        --user david \
        --pass "DavidPass123!" \
        --real "David Park" \
        --quota 500 \
        --mail-quota 200 2>&1 || echo "WARNING: create-user returned non-zero"
    sleep 2
else
    echo "User david already exists"
fi

# Record initial autoresponder state for anti-gaming
echo "Recording initial state..."
virtualmin list-users --domain acmecorp.test --user-name sarah --multiline > /tmp/sarah_initial_state.txt 2>/dev/null || true

# Verify autoresponder is NOT enabled initially
if grep -qi "autorespond\|auto.reply\|vacation" /tmp/sarah_initial_state.txt 2>/dev/null; then
    echo "Disabling any existing autoresponder..."
    virtualmin modify-user \
        --domain acmecorp.test \
        --user sarah \
        --no-autoresponder 2>/dev/null || true
fi

# Store the expected autoreply file paths for verification
SARAH_HOME=$(virtualmin list-users --domain acmecorp.test --user-name sarah --multiline 2>/dev/null | grep "Home directory" | awk '{print $NF}')
if [ -z "$SARAH_HOME" ]; then
    # Fallback: try common paths
    SARAH_HOME="/home/acmecorp/homes/sarah"
fi
echo "$SARAH_HOME" > /tmp/sarah_home_path.txt

# Remove any existing autoreply files to ensure clean state
rm -f "${SARAH_HOME}/autoreply.txt" 2>/dev/null || true
rm -f "${SARAH_HOME}/.autoreply.txt" 2>/dev/null || true
rm -f "${SARAH_HOME}/autoreply.msg" 2>/dev/null || true

echo "Sarah's home directory: $SARAH_HOME"

# Ensure Firefox is ready and navigate to Virtualmin
ensure_virtualmin_ready
sleep 3

# Navigate to the acmecorp.test domain in Virtualmin
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/summary_domain.cgi?dom=${DOMAIN_ID}"
else
    navigate_to "https://localhost:10000/virtual-server/index.cgi"
fi
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Users created: sarah@acmecorp.test, david@acmecorp.test"
echo "Autoresponder is currently OFF for sarah"