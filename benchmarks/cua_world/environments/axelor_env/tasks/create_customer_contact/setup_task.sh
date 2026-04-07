#!/bin/bash
echo "=== Setting up create_customer_contact task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Remove any pre-existing "Warby Parker" partner for idempotency ────
echo "--- Cleaning up existing data ---"
axelor_query "DELETE FROM base_partner WHERE LOWER(name) LIKE '%warby parker%';" || true

# ── 2. Record initial partner count ──────────────────────────────────────
INITIAL_COUNT=$(get_partner_count)
echo "Initial partner count: ${INITIAL_COUNT}"
echo "${INITIAL_COUNT}" > /tmp/create_customer_initial_count

# ── 3. Record task start timestamp ───────────────────────────────────────
date +%s > /tmp/task_start_timestamp

# ── 4. Ensure Axelor is logged in and navigate to partner list ───────────
echo "--- Navigating to partner list ---"
ensure_axelor_logged_in "${AXELOR_URL}/"
sleep 3

# ── 5. Take initial screenshot ───────────────────────────────────────────
take_screenshot /tmp/create_customer_contact_initial.png

echo "=== create_customer_contact task setup complete ==="
echo "Agent should create a new customer: Warby Parker Inc."
