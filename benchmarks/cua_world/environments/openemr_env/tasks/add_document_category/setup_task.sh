#!/bin/bash
# Setup script for Add Document Category task
set -e
echo "=== Setting up Add Document Category task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial category count for verification
echo "Recording initial category state..."
INITIAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM categories" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_category_count.txt
echo "Initial category count: $INITIAL_COUNT"

# Record max category ID (to detect newly created categories)
MAX_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COALESCE(MAX(id), 0) FROM categories" 2>/dev/null || echo "0")
echo "$MAX_ID" > /tmp/initial_max_category_id.txt
echo "Initial max category ID: $MAX_ID"

# Check if a "Prior Authorization" category already exists and remove it for clean test
EXISTING=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM categories WHERE LOWER(name) LIKE '%prior%' AND LOWER(name) LIKE '%auth%'" 2>/dev/null || echo "0")
if [ "$EXISTING" -gt 0 ]; then
    echo "Cleaning up existing Prior Authorization category..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "DELETE FROM categories WHERE LOWER(name) LIKE '%prior%' AND LOWER(name) LIKE '%auth%'" 2>/dev/null || true
    
    # Update counts after cleanup
    INITIAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT COUNT(*) FROM categories" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_category_count.txt
    echo "Updated initial category count after cleanup: $INITIAL_COUNT"
fi

# List existing categories for debugging
echo ""
echo "=== Existing document categories ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT id, name, parent FROM categories ORDER BY id" 2>/dev/null | head -20
echo ""

# Ensure Firefox is running with OpenEMR
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox with OpenEMR..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openemr"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Maximize and focus Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Found Firefox window: $WID"
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for verification
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Add Document Category Task Setup Complete ==="
echo ""
echo "Task: Create a new document category called 'Prior Authorizations'"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (Username: admin, Password: pass)"
echo "  2. Navigate to Administration > Other > Document Categories"
echo "  3. Add a new category named: Prior Authorizations"
echo "  4. Save the new category"
echo ""
echo "Initial category count: $INITIAL_COUNT"
echo "Initial max category ID: $MAX_ID"
echo ""