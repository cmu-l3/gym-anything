#!/bin/bash
echo "=== Setting up hardware_recall_processing task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Create the CPSC Recall Notice PDF
# ---------------------------------------------------------------
echo "  Generating official CPSC Recall Notice PDF..."
mkdir -p /home/ga/Documents
python3 -c "
import matplotlib.pyplot as plt
plt.figure(figsize=(8.5, 11))
plt.text(0.5, 0.85, 'URGENT CPSC RECALL NOTICE', fontsize=24, ha='center', color='red', weight='bold')
plt.text(0.5, 0.7, 'Model: HP EliteBook 840 G7', fontsize=18, ha='center', weight='bold')
plt.text(0.5, 0.55, 'Hazard: The lithium-ion battery can overheat,\nposing a fire hazard.', fontsize=16, ha='center')
plt.text(0.5, 0.4, 'Action: Quarantine immediately.\nDo not deploy to staff.', fontsize=16, ha='center')
plt.axis('off')
plt.savefig('/home/ga/Documents/CPSC_Recall_Notice.pdf', bbox_inches='tight')
" 2>/dev/null || echo "Recall Notice - Quarantine HP EliteBook 840 G7" > /home/ga/Documents/CPSC_Recall_Notice.pdf

chown ga:ga /home/ga/Documents/CPSC_Recall_Notice.pdf

# Helper function
get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

# ---------------------------------------------------------------
# 2. Setup Base Data (Categories, Manufacturers, Models)
# ---------------------------------------------------------------
echo "  Setting up required data in Snipe-IT..."
MAN_HP=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='HP' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MAN_HP" ]; then
    MAN_HP=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"HP"}')")
fi

CAT_LAPTOP=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')

# Create Models
G7_MODEL_ID=$(get_id "$(snipeit_api POST "models" "{\"name\":\"HP EliteBook 840 G7\", \"category_id\":$CAT_LAPTOP, \"manufacturer_id\":$MAN_HP}")")
G8_MODEL_ID=$(get_id "$(snipeit_api POST "models" "{\"name\":\"HP EliteBook 840 G8\", \"category_id\":$CAT_LAPTOP, \"manufacturer_id\":$MAN_HP}")")

# Fallback in case of API jq failure
if [ -z "$G7_MODEL_ID" ]; then G7_MODEL_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='HP EliteBook 840 G7' LIMIT 1" | tr -d '[:space:]'); fi
if [ -z "$G8_MODEL_ID" ]; then G8_MODEL_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='HP EliteBook 840 G8' LIMIT 1" | tr -d '[:space:]'); fi

echo "$G7_MODEL_ID" > /tmp/g7_model_id.txt
echo "$G8_MODEL_ID" > /tmp/g8_model_id.txt

# ---------------------------------------------------------------
# 3. Inject Target Assets (G7 and G8)
# ---------------------------------------------------------------
USER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username!='admin' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
if [ -z "$USER_ID" ]; then USER_ID=1; fi
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

A1=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"HP-G7-001\", \"name\":\"Laptop G7 1\", \"model_id\":$G7_MODEL_ID, \"status_id\":$SL_READY}")")
A2=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"HP-G7-002\", \"name\":\"Laptop G7 2\", \"model_id\":$G7_MODEL_ID, \"status_id\":$SL_READY}")")
A3=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"HP-G7-003\", \"name\":\"Laptop G7 3\", \"model_id\":$G7_MODEL_ID, \"status_id\":$SL_READY}")")

B1=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"HP-G8-001\", \"name\":\"Laptop G8 1\", \"model_id\":$G8_MODEL_ID, \"status_id\":$SL_READY}")")
B2=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"HP-G8-002\", \"name\":\"Laptop G8 2\", \"model_id\":$G8_MODEL_ID, \"status_id\":$SL_READY}")")
B3=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"HP-G8-003\", \"name\":\"Laptop G8 3\", \"model_id\":$G8_MODEL_ID, \"status_id\":$SL_READY}")")

sleep 2

# Checkout 2 of each model to simulate active deployment
snipeit_api POST "hardware/${A1}/checkout" "{\"checkout_to_type\":\"user\", \"assigned_user\":$USER_ID}" > /dev/null
snipeit_api POST "hardware/${A2}/checkout" "{\"checkout_to_type\":\"user\", \"assigned_user\":$USER_ID}" > /dev/null
snipeit_api POST "hardware/${B1}/checkout" "{\"checkout_to_type\":\"user\", \"assigned_user\":$USER_ID}" > /dev/null
snipeit_api POST "hardware/${B2}/checkout" "{\"checkout_to_type\":\"user\", \"assigned_user\":$USER_ID}" > /dev/null

sleep 2

# ---------------------------------------------------------------
# 4. Record Baselines for Anti-Gaming Verification
# ---------------------------------------------------------------
echo "  Recording baseline state..."

# Initial G7 checkout count
G7_INITIAL_CHECKED_IN=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE model_id=$G7_MODEL_ID AND (assigned_to IS NULL OR assigned_to=0) AND deleted_at IS NULL" | tr -d '[:space:]')
echo "$G7_INITIAL_CHECKED_IN" > /tmp/g7_initial_checked_in.txt

# Snapshot of all G8 assets to ensure they aren't tampered with
snipeit_db_query "SELECT id, status_id, COALESCE(assigned_to, 0) FROM assets WHERE model_id=$G8_MODEL_ID AND deleted_at IS NULL ORDER BY id" > /tmp/g8_baseline.txt

# Start timestamp
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 5. UI Setup
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3

take_screenshot /tmp/task_initial.png

echo "=== hardware_recall_processing task setup complete ==="