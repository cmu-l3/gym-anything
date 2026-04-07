#!/bin/bash
echo "=== Setting up cybersecurity_incident_quarantine task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming / action log verification)
date +%s > /tmp/task_start_time.txt

# 1. Gather existing IDs to build our target assets
CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE category_type='asset' LIMIT 1" | tr -d '[:space:]')
MOD_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
LOC_ID=$(snipeit_db_query "SELECT id FROM locations LIMIT 1" | tr -d '[:space:]')
STATUS_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' OR deployable=1 LIMIT 1" | tr -d '[:space:]')

echo "Using Category: $CAT_ID, Model: $MOD_ID, Location: $LOC_ID, Status: $STATUS_READY_ID"

# 2. Helper to fetch jq-parsed IDs from Snipe-IT API responses
get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

# 3. Create Users
echo "--- Creating Target & Control Users ---"
U1_ID=$(get_id "$(snipeit_api POST "users" '{"first_name":"Sarah","last_name":"Jenkins","username":"sjenkins","password":"password123"}')")
U2_ID=$(get_id "$(snipeit_api POST "users" '{"first_name":"Mike","last_name":"Chen","username":"mchen","password":"password123"}')")
U3_ID=$(get_id "$(snipeit_api POST "users" '{"first_name":"Alex","last_name":"Wong","username":"awong","password":"password123"}')")
U4_ID=$(get_id "$(snipeit_api POST "users" '{"first_name":"David","last_name":"Torres","username":"dtorres","password":"password123"}')")
U5_ID=$(get_id "$(snipeit_api POST "users" '{"first_name":"Emma","last_name":"Smith","username":"esmith","password":"password123"}')")

# Fallback to DB if API creation fails
if [ -z "$U1_ID" ]; then U1_ID=$(snipeit_db_query "SELECT id FROM users ORDER BY RAND() LIMIT 1" | tr -d '[:space:]'); fi
if [ -z "$U2_ID" ]; then U2_ID=$(snipeit_db_query "SELECT id FROM users ORDER BY RAND() LIMIT 1" | tr -d '[:space:]'); fi
if [ -z "$U3_ID" ]; then U3_ID=$(snipeit_db_query "SELECT id FROM users ORDER BY RAND() LIMIT 1" | tr -d '[:space:]'); fi
if [ -z "$U4_ID" ]; then U4_ID=$(snipeit_db_query "SELECT id FROM users ORDER BY RAND() LIMIT 1" | tr -d '[:space:]'); fi
if [ -z "$U5_ID" ]; then U5_ID=$(snipeit_db_query "SELECT id FROM users ORDER BY RAND() LIMIT 1" | tr -d '[:space:]'); fi

# 4. Create and checkout Compromised Assets (Targets)
echo "--- Injecting Target Assets ---"
A1_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"MAC-9912\",\"name\":\"LPT-MKT-04\",\"model_id\":$MOD_ID,\"status_id\":$STATUS_READY_ID,\"notes\":\"Standard issue\"}")")
snipeit_api POST "hardware/${A1_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$U1_ID}" >/dev/null

A2_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"DELL-441A\",\"name\":\"LPT-SALES-11\",\"model_id\":$MOD_ID,\"status_id\":$STATUS_READY_ID,\"notes\":\"Standard issue\"}")")
snipeit_api POST "hardware/${A2_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$U2_ID}" >/dev/null

A3_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"HP-8812\",\"name\":\"LPT-HR-02\",\"model_id\":$MOD_ID,\"status_id\":$STATUS_READY_ID,\"notes\":\"Standard issue\"}")")
snipeit_api POST "hardware/${A3_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$U3_ID}" >/dev/null

# 5. Create and checkout Control Assets (Must not be modified)
echo "--- Injecting Control Assets ---"
A4_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"MAC-0001\",\"name\":\"LPT-EXEC-01\",\"model_id\":$MOD_ID,\"status_id\":$STATUS_READY_ID,\"notes\":\"Executive device\"}")")
snipeit_api POST "hardware/${A4_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$U4_ID}" >/dev/null

A5_ID=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"DELL-998B\",\"name\":\"LPT-DEV-09\",\"model_id\":$MOD_ID,\"status_id\":$STATUS_READY_ID,\"notes\":\"Developer machine\"}")")
snipeit_api POST "hardware/${A5_ID}/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$U5_ID}" >/dev/null

# Clear any rogue existing "Quarantined - Forensic Hold" labels to start clean
snipeit_db_query "DELETE FROM status_labels WHERE name='Quarantined - Forensic Hold'" 2>/dev/null || true

# 6. Open Firefox and setup window
ensure_firefox_snipeit
navigate_firefox_to "http://localhost:8000"
sleep 2

take_screenshot /tmp/task_initial.png
echo "=== Setup complete ==="