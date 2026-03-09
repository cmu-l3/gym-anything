#!/bin/bash
set -e
echo "=== Setting up clone_virtual_server task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Record initial domain count
INITIAL_COUNT=$(virtualmin list-domains --name-only 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_domain_count.txt
echo "Initial domain count: $INITIAL_COUNT"

# 2. Ensure source domain acmecorp.test exists
if ! virtualmin list-domains --name-only 2>/dev/null | grep -q "^acmecorp.test$"; then
    echo "ERROR: Source domain acmecorp.test missing. Attempting to recreate..."
    # Re-run environment setup logic for this specific domain if missing
    virtualmin create-domain --domain acmecorp.test --pass GymAnything123! --unix --dir --webmin --web --dns --mail --mysql 2>/dev/null || true
fi

# 3. Clean up target domain if it exists (idempotency)
if virtualmin list-domains --name-only 2>/dev/null | grep -q "^acmecorp-staging.test$"; then
    echo "Cleaning up previous run artifacts..."
    virtualmin delete-domain --domain acmecorp-staging.test --yes 2>&1 >/dev/null || true
    sleep 3
fi

# 4. Record source domain stats for comparison (Anti-gaming)
# We want to verify files are actually copied, not just an empty domain created
SOURCE_HOME=$(virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null | grep "Home directory" | awk '{print $NF}')
if [ -n "$SOURCE_HOME" ] && [ -d "$SOURCE_HOME/public_html" ]; then
    # Create a dummy file to ensure there's something to copy
    echo "Staging Test $(date)" > "$SOURCE_HOME/public_html/staging_test_marker.txt"
    
    FILE_COUNT=$(find "$SOURCE_HOME/public_html" -type f 2>/dev/null | wc -l)
    echo "$FILE_COUNT" > /tmp/source_file_count.txt
    echo "Source file count: $FILE_COUNT"
else
    echo "0" > /tmp/source_file_count.txt
fi

# 5. Prepare Application State (Firefox)
ensure_virtualmin_ready

# Navigate specifically to the source domain's summary page to guide the agent
# This reduces the search space slightly, focusing them on the correct starting point
SOURCE_ID=$(get_domain_id "acmecorp.test")
if [ -n "$SOURCE_ID" ]; then
    echo "Navigating to acmecorp.test summary..."
    navigate_to "${VIRTUALMIN_URL}/virtual-server/summary_domain.cgi?dom=${SOURCE_ID}"
else
    navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi"
fi
sleep 3

# 6. Capture initial state evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="