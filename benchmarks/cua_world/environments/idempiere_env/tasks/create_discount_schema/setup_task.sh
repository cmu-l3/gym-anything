#!/bin/bash
set -e
echo "=== Setting up create_discount_schema task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Clean up existing data (Idempotency)
# ---------------------------------------------------------------
echo "--- Cleaning up any existing schemas with target name ---"
TARGET_NAME="Bulk Order Incentive 2024"

# Get ID if exists
SCHEMA_ID=$(idempiere_query "SELECT m_discountschema_id FROM m_discountschema WHERE name='$TARGET_NAME'" 2>/dev/null || echo "")

if [ -n "$SCHEMA_ID" ] && [ "$SCHEMA_ID" != "0" ]; then
    echo "Found existing schema (ID: $SCHEMA_ID), deleting..."
    # Delete breaks first (foreign key constraint)
    idempiere_query "DELETE FROM m_discountschemabreak WHERE m_discountschema_id=$SCHEMA_ID"
    # Delete header
    idempiere_query "DELETE FROM m_discountschema WHERE m_discountschema_id=$SCHEMA_ID"
else
    echo "No existing schema found."
fi

# ---------------------------------------------------------------
# 2. Record Initial State
# ---------------------------------------------------------------
# Record count of discount schemas
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_discountschema" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_schema_count.txt
echo "Initial Schema Count: $INITIAL_COUNT"

# ---------------------------------------------------------------
# 3. Ensure Application is Ready
# ---------------------------------------------------------------
echo "--- Checking Firefox and iDempiere connection ---"
# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
            break
        fi
        sleep 1
    done
fi

# Navigate to dashboard/home to ensure clean UI state
navigate_to_dashboard

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure focus
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# ---------------------------------------------------------------
# 4. Capture Initial Screenshot
# ---------------------------------------------------------------
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="