#!/bin/bash
echo "=== Setting up end_of_quarter_it_reconciliation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Helper to extract ID from API response
get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

# ---------------------------------------------------------------
# 1. Get existing status label and model IDs from base seed
# ---------------------------------------------------------------
echo "  Looking up base seed IDs..."

SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
SL_DEPLOYED_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')
SL_REPAIR_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Out for Repair' LIMIT 1" | tr -d '[:space:]')

echo "  Status IDs: ready=$SL_READY_ID deployed=$SL_DEPLOYED_ID repair=$SL_REPAIR_ID"

# Models (all exist in base seed)
MDL_LAT5540=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Latitude 5540%' LIMIT 1" | tr -d '[:space:]')
MDL_EB840=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%EliteBook 840%' LIMIT 1" | tr -d '[:space:]')
MDL_T14S=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%ThinkPad T14s%' LIMIT 1" | tr -d '[:space:]')
MDL_LAT7440=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Latitude 7440%' LIMIT 1" | tr -d '[:space:]')
MDL_MBP16=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%MacBook Pro 16%' LIMIT 1" | tr -d '[:space:]')
MDL_OPTIPLEX=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%OptiPlex 7010%' LIMIT 1" | tr -d '[:space:]')
MDL_U2723=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%U2723%' LIMIT 1" | tr -d '[:space:]')
MDL_ODYSSEY=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%Odyssey%' LIMIT 1" | tr -d '[:space:]')

echo "  Model IDs: lat5540=$MDL_LAT5540 eb840=$MDL_EB840 t14s=$MDL_T14S lat7440=$MDL_LAT7440 mbp16=$MDL_MBP16 optiplex=$MDL_OPTIPLEX u2723=$MDL_U2723 odyssey=$MDL_ODYSSEY"

# Categories
CAT_LAPTOPS=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
CAT_DESKTOPS=$(snipeit_db_query "SELECT id FROM categories WHERE name='Desktops' LIMIT 1" | tr -d '[:space:]')
CAT_MONITORS=$(snipeit_db_query "SELECT id FROM categories WHERE name='Monitors' LIMIT 1" | tr -d '[:space:]')

# Departments (all exist in base seed)
DEPT_HR=$(snipeit_db_query "SELECT id FROM departments WHERE name LIKE '%Human Resources%' OR name='HR' LIMIT 1" | tr -d '[:space:]')
DEPT_FINANCE=$(snipeit_db_query "SELECT id FROM departments WHERE name='Finance' LIMIT 1" | tr -d '[:space:]')
DEPT_ENGINEERING=$(snipeit_db_query "SELECT id FROM departments WHERE name='Engineering' LIMIT 1" | tr -d '[:space:]')
DEPT_IT=$(snipeit_db_query "SELECT id FROM departments WHERE name LIKE '%Information Technology%' OR name='IT' LIMIT 1" | tr -d '[:space:]')
DEPT_SALES=$(snipeit_db_query "SELECT id FROM departments WHERE name='Sales' LIMIT 1" | tr -d '[:space:]')
DEPT_MARKETING=$(snipeit_db_query "SELECT id FROM departments WHERE name='Marketing' LIMIT 1" | tr -d '[:space:]')

echo "  Dept IDs: hr=$DEPT_HR finance=$DEPT_FINANCE eng=$DEPT_ENGINEERING it=$DEPT_IT sales=$DEPT_SALES marketing=$DEPT_MARKETING"

# Locations (all exist in base seed)
LOC_HQA=$(snipeit_db_query "SELECT id FROM locations WHERE name LIKE '%Building A%' LIMIT 1" | tr -d '[:space:]')
LOC_HQB=$(snipeit_db_query "SELECT id FROM locations WHERE name LIKE '%Building B%' LIMIT 1" | tr -d '[:space:]')
LOC_NYC=$(snipeit_db_query "SELECT id FROM locations WHERE name LIKE '%New York%' LIMIT 1" | tr -d '[:space:]')
LOC_AUSTIN=$(snipeit_db_query "SELECT id FROM locations WHERE name LIKE '%Austin%' LIMIT 1" | tr -d '[:space:]')
LOC_LONDON=$(snipeit_db_query "SELECT id FROM locations WHERE name LIKE '%London%' LIMIT 1" | tr -d '[:space:]')

echo "  Location IDs: hqa=$LOC_HQA hqb=$LOC_HQB nyc=$LOC_NYC austin=$LOC_AUSTIN london=$LOC_LONDON"

# Microsoft 365 license
MS365_ID=$(snipeit_db_query "SELECT id FROM licenses WHERE name LIKE '%Microsoft 365%' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
echo "  M365 license ID: $MS365_ID"

# ---------------------------------------------------------------
# 2. Clean up any pre-existing task data
# ---------------------------------------------------------------
echo "  Cleaning up pre-existing task data..."

# Remove task-specific assets
for tag in RECON-L001 RECON-L002 RECON-L003 RECON-L004 RECON-L005 RECON-L006 RECON-S001 RECON-S002 RECON-MON-A RECON-D001 RECON-MON-B; do
    EXISTING_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='$tag'" | tr -d '[:space:]')
    if [ -n "$EXISTING_ID" ]; then
        # Remove from action_logs first to avoid FK issues
        snipeit_db_query "DELETE FROM action_logs WHERE item_id=$EXISTING_ID AND item_type LIKE '%Asset%'" 2>/dev/null || true
        # Remove license seat checkouts
        snipeit_db_query "DELETE FROM license_seats WHERE assigned_to=$EXISTING_ID" 2>/dev/null || true
        snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'"
    fi
done

# Remove task-specific users
for uname in alee bkumar dmiller ezhang fsingh gpark mrivera ytanaka; do
    EXISTING_UID=$(snipeit_db_query "SELECT id FROM users WHERE username='$uname'" | tr -d '[:space:]')
    if [ -n "$EXISTING_UID" ]; then
        # Remove license seat assignments
        snipeit_db_query "UPDATE license_seats SET assigned_to=NULL WHERE assigned_to=$EXISTING_UID" 2>/dev/null || true
        # Remove asset assignments
        snipeit_db_query "UPDATE assets SET assigned_to=NULL, assigned_type=NULL WHERE assigned_to=$EXISTING_UID AND assigned_type LIKE '%User%'" 2>/dev/null || true
        snipeit_db_query "DELETE FROM users WHERE username='$uname'"
    fi
done

# Remove task-specific location if it exists
snipeit_db_query "DELETE FROM locations WHERE name='Building C - Floor 3'" 2>/dev/null || true

# Revert Marketing department name if it was renamed
snipeit_db_query "UPDATE departments SET name='Marketing' WHERE name='Growth & Marketing'" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create the 6 task-specific users
# ---------------------------------------------------------------
echo "  Creating task users..."

# Departing employees
ALEE_RESP=$(snipeit_api POST "users" "{\"first_name\":\"Alex\",\"last_name\":\"Lee\",\"username\":\"alee\",\"password\":\"password\",\"password_confirmation\":\"password\",\"email\":\"alee@example.com\",\"activated\":true,\"department_id\":$DEPT_HR,\"location_id\":$LOC_HQB}")
ALEE_ID=$(get_id "$ALEE_RESP")
if [ -z "$ALEE_ID" ]; then
    ALEE_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='alee' LIMIT 1" | tr -d '[:space:]')
fi
echo "  alee ID: $ALEE_ID"

BKUMAR_RESP=$(snipeit_api POST "users" "{\"first_name\":\"Bianca\",\"last_name\":\"Kumar\",\"username\":\"bkumar\",\"password\":\"password\",\"password_confirmation\":\"password\",\"email\":\"bkumar@example.com\",\"activated\":true,\"department_id\":$DEPT_FINANCE,\"location_id\":$LOC_NYC}")
BKUMAR_ID=$(get_id "$BKUMAR_RESP")
if [ -z "$BKUMAR_ID" ]; then
    BKUMAR_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='bkumar' LIMIT 1" | tr -d '[:space:]')
fi
echo "  bkumar ID: $BKUMAR_ID"

# Staying employees
DMILLER_RESP=$(snipeit_api POST "users" "{\"first_name\":\"Diana\",\"last_name\":\"Miller\",\"username\":\"dmiller\",\"password\":\"password\",\"password_confirmation\":\"password\",\"email\":\"dmiller@example.com\",\"activated\":true,\"department_id\":$DEPT_ENGINEERING,\"location_id\":$LOC_HQA}")
DMILLER_ID=$(get_id "$DMILLER_RESP")
if [ -z "$DMILLER_ID" ]; then
    DMILLER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='dmiller' LIMIT 1" | tr -d '[:space:]')
fi
echo "  dmiller ID: $DMILLER_ID"

EZHANG_RESP=$(snipeit_api POST "users" "{\"first_name\":\"Ethan\",\"last_name\":\"Zhang\",\"username\":\"ezhang\",\"password\":\"password\",\"password_confirmation\":\"password\",\"email\":\"ezhang@example.com\",\"activated\":true,\"department_id\":$DEPT_IT,\"location_id\":$LOC_AUSTIN}")
EZHANG_ID=$(get_id "$EZHANG_RESP")
if [ -z "$EZHANG_ID" ]; then
    EZHANG_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='ezhang' LIMIT 1" | tr -d '[:space:]')
fi
echo "  ezhang ID: $EZHANG_ID"

FSINGH_RESP=$(snipeit_api POST "users" "{\"first_name\":\"Fatima\",\"last_name\":\"Singh\",\"username\":\"fsingh\",\"password\":\"password\",\"password_confirmation\":\"password\",\"email\":\"fsingh@example.com\",\"activated\":true,\"department_id\":$DEPT_SALES,\"location_id\":$LOC_LONDON}")
FSINGH_ID=$(get_id "$FSINGH_RESP")
if [ -z "$FSINGH_ID" ]; then
    FSINGH_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='fsingh' LIMIT 1" | tr -d '[:space:]')
fi
echo "  fsingh ID: $FSINGH_ID"

GPARK_RESP=$(snipeit_api POST "users" "{\"first_name\":\"Grace\",\"last_name\":\"Park\",\"username\":\"gpark\",\"password\":\"password\",\"password_confirmation\":\"password\",\"email\":\"gpark@example.com\",\"activated\":true,\"department_id\":$DEPT_ENGINEERING,\"location_id\":$LOC_HQA}")
GPARK_ID=$(get_id "$GPARK_RESP")
if [ -z "$GPARK_ID" ]; then
    GPARK_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='gpark' LIMIT 1" | tr -d '[:space:]')
fi
echo "  gpark ID: $GPARK_ID"

sleep 2

# ---------------------------------------------------------------
# 4. Create assets
# ---------------------------------------------------------------
echo "  Creating task assets..."

# --- Departing employees' hardware ---
# alee: laptop (active warranty) + monitor
RECON_L001_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-L001\",\"name\":\"Dell Latitude 5540 - Alex Lee\",\"model_id\":$MDL_LAT5540,\"status_id\":$SL_READY_ID,\"serial\":\"FL-DL5540-001\",\"purchase_date\":\"2024-07-01\",\"purchase_cost\":1299.99,\"warranty_months\":36,\"rtd_location_id\":$LOC_HQB}")
RECON_L001_ID=$(get_id "$RECON_L001_RESP")
if [ -z "$RECON_L001_ID" ]; then
    RECON_L001_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-L001' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-L001 ID: $RECON_L001_ID"

RECON_MONA_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-MON-A\",\"name\":\"Dell U2723QE Monitor - Alex Lee\",\"model_id\":$MDL_U2723,\"status_id\":$SL_READY_ID,\"serial\":\"FL-MONA-001\",\"purchase_date\":\"2024-03-15\",\"purchase_cost\":549.99,\"warranty_months\":36,\"rtd_location_id\":$LOC_HQB}")
RECON_MONA_ID=$(get_id "$RECON_MONA_RESP")
if [ -z "$RECON_MONA_ID" ]; then
    RECON_MONA_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-MON-A' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-MON-A ID: $RECON_MONA_ID"

# bkumar: laptop (expired warranty)
RECON_L002_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-L002\",\"name\":\"HP EliteBook 840 G10 - Bianca Kumar\",\"model_id\":$MDL_EB840,\"status_id\":$SL_READY_ID,\"serial\":\"FL-HP840-002\",\"purchase_date\":\"2023-02-15\",\"purchase_cost\":1349.99,\"warranty_months\":24,\"rtd_location_id\":$LOC_NYC}")
RECON_L002_ID=$(get_id "$RECON_L002_RESP")
if [ -z "$RECON_L002_ID" ]; then
    RECON_L002_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-L002' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-L002 ID: $RECON_L002_ID"

# --- Warranty audit target laptops (expired, deployed to staying employees) ---
# dmiller: laptop, purchased 2022-08-10, 36mo warranty -> expired 2025-08-10
RECON_L003_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-L003\",\"name\":\"Lenovo ThinkPad T14s Gen 4 - Diana Miller\",\"model_id\":$MDL_T14S,\"status_id\":$SL_READY_ID,\"serial\":\"FL-LT14S-003\",\"purchase_date\":\"2022-08-10\",\"purchase_cost\":1449.99,\"warranty_months\":36,\"rtd_location_id\":$LOC_HQA}")
RECON_L003_ID=$(get_id "$RECON_L003_RESP")
if [ -z "$RECON_L003_ID" ]; then
    RECON_L003_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-L003' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-L003 ID: $RECON_L003_ID"

# ezhang: laptop, purchased 2023-06-20, 24mo warranty -> expired 2025-06-20
RECON_L004_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-L004\",\"name\":\"Dell Latitude 7440 - Ethan Zhang\",\"model_id\":$MDL_LAT7440,\"status_id\":$SL_READY_ID,\"serial\":\"FL-DL7440-004\",\"purchase_date\":\"2023-06-20\",\"purchase_cost\":1599.99,\"warranty_months\":24,\"rtd_location_id\":$LOC_AUSTIN}")
RECON_L004_ID=$(get_id "$RECON_L004_RESP")
if [ -z "$RECON_L004_ID" ]; then
    RECON_L004_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-L004' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-L004 ID: $RECON_L004_ID"

# --- Active warranty laptops (must NOT be modified) ---
# fsingh: laptop, purchased 2024-09-01, 36mo -> expires 2027-09-01
RECON_L005_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-L005\",\"name\":\"MacBook Pro 16-inch M3 Pro - Fatima Singh\",\"model_id\":$MDL_MBP16,\"status_id\":$SL_READY_ID,\"serial\":\"FL-MBP16-005\",\"purchase_date\":\"2024-09-01\",\"purchase_cost\":2499.99,\"warranty_months\":36,\"rtd_location_id\":$LOC_LONDON}")
RECON_L005_ID=$(get_id "$RECON_L005_RESP")
if [ -z "$RECON_L005_ID" ]; then
    RECON_L005_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-L005' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-L005 ID: $RECON_L005_ID"

# gpark: laptop, purchased 2024-11-15, 36mo -> expires 2027-11-15
RECON_L006_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-L006\",\"name\":\"HP EliteBook 840 G10 - Grace Park\",\"model_id\":$MDL_EB840,\"status_id\":$SL_READY_ID,\"serial\":\"FL-HP840-006\",\"purchase_date\":\"2024-11-15\",\"purchase_cost\":1349.99,\"warranty_months\":36,\"rtd_location_id\":$LOC_HQA}")
RECON_L006_ID=$(get_id "$RECON_L006_RESP")
if [ -z "$RECON_L006_ID" ]; then
    RECON_L006_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-L006' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-L006 ID: $RECON_L006_ID"

# --- Spare laptops (Ready to Deploy, for new hire provisioning) ---
RECON_S001_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-S001\",\"name\":\"Dell Latitude 5540 - Spare\",\"model_id\":$MDL_LAT5540,\"status_id\":$SL_READY_ID,\"serial\":\"FL-DL5540-S01\",\"purchase_date\":\"2025-01-10\",\"purchase_cost\":1299.99,\"warranty_months\":36,\"rtd_location_id\":$LOC_HQA}")
RECON_S001_ID=$(get_id "$RECON_S001_RESP")
if [ -z "$RECON_S001_ID" ]; then
    RECON_S001_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-S001' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-S001 ID: $RECON_S001_ID"

RECON_S002_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-S002\",\"name\":\"Lenovo ThinkPad T14s Gen 4 - Spare\",\"model_id\":$MDL_T14S,\"status_id\":$SL_READY_ID,\"serial\":\"FL-LT14S-S02\",\"purchase_date\":\"2025-02-01\",\"purchase_cost\":1449.99,\"warranty_months\":36,\"rtd_location_id\":$LOC_NYC}")
RECON_S002_ID=$(get_id "$RECON_S002_RESP")
if [ -z "$RECON_S002_ID" ]; then
    RECON_S002_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-S002' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-S002 ID: $RECON_S002_ID"

# --- Non-laptop distractors (expired warranty, should NOT be flagged in Phase 3) ---
# Desktop with expired warranty, checked out to dmiller
RECON_D001_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-D001\",\"name\":\"Dell OptiPlex 7010 - Diana Miller Desktop\",\"model_id\":$MDL_OPTIPLEX,\"status_id\":$SL_READY_ID,\"serial\":\"FL-DOPT-D01\",\"purchase_date\":\"2022-03-01\",\"purchase_cost\":899.99,\"warranty_months\":24,\"rtd_location_id\":$LOC_HQA}")
RECON_D001_ID=$(get_id "$RECON_D001_RESP")
if [ -z "$RECON_D001_ID" ]; then
    RECON_D001_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-D001' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-D001 ID: $RECON_D001_ID"

# Monitor with expired warranty, unassigned
RECON_MONB_RESP=$(snipeit_api POST "hardware" "{\"asset_tag\":\"RECON-MON-B\",\"name\":\"Samsung Odyssey G5 34in - Storage\",\"model_id\":$MDL_ODYSSEY,\"status_id\":$SL_READY_ID,\"serial\":\"FL-MON-B01\",\"purchase_date\":\"2022-05-01\",\"purchase_cost\":399.99,\"warranty_months\":24,\"rtd_location_id\":$LOC_HQB}")
RECON_MONB_ID=$(get_id "$RECON_MONB_RESP")
if [ -z "$RECON_MONB_ID" ]; then
    RECON_MONB_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='RECON-MON-B' LIMIT 1" | tr -d '[:space:]')
fi
echo "    RECON-MON-B ID: $RECON_MONB_ID"

sleep 2

# ---------------------------------------------------------------
# 5. Check out assets to users
# ---------------------------------------------------------------
echo "  Checking out assets to users..."

# alee gets laptop + monitor
snipeit_api POST "hardware/$RECON_L001_ID/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$ALEE_ID,\"note\":\"HR department workstation\"}"
sleep 1
snipeit_api POST "hardware/$RECON_MONA_ID/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$ALEE_ID,\"note\":\"HR department monitor\"}"
sleep 1

# bkumar gets laptop
snipeit_api POST "hardware/$RECON_L002_ID/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$BKUMAR_ID,\"note\":\"Finance department workstation\"}"
sleep 1

# dmiller gets laptop + desktop (distractor)
snipeit_api POST "hardware/$RECON_L003_ID/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$DMILLER_ID,\"note\":\"Engineering workstation\"}"
sleep 1
snipeit_api POST "hardware/$RECON_D001_ID/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$DMILLER_ID,\"note\":\"Engineering desktop\"}"
sleep 1

# ezhang gets laptop
snipeit_api POST "hardware/$RECON_L004_ID/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$EZHANG_ID,\"note\":\"IT department workstation\"}"
sleep 1

# fsingh gets laptop
snipeit_api POST "hardware/$RECON_L005_ID/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$FSINGH_ID,\"note\":\"Sales department workstation\"}"
sleep 1

# gpark gets laptop
snipeit_api POST "hardware/$RECON_L006_ID/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$GPARK_ID,\"note\":\"Engineering workstation\"}"
sleep 1

echo "  All checkouts complete."

# ---------------------------------------------------------------
# 6. Assign Microsoft 365 license seats
#    alee, bkumar, dmiller, fsingh, gpark get seats
#    ezhang does NOT get a seat (to test Phase 4 compliance)
# ---------------------------------------------------------------
echo "  Assigning M365 license seats..."

for USER_ID in $ALEE_ID $BKUMAR_ID $DMILLER_ID $FSINGH_ID $GPARK_ID; do
    if [ -n "$USER_ID" ] && [ -n "$MS365_ID" ]; then
        # Use direct DB update — the Snipe-IT API for license seat checkout is unreliable
        SEAT_ID=$(snipeit_db_query "SELECT id FROM license_seats WHERE license_id=$MS365_ID AND assigned_to IS NULL AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
        if [ -n "$SEAT_ID" ]; then
            snipeit_db_query "UPDATE license_seats SET assigned_to=$USER_ID WHERE id=$SEAT_ID AND assigned_to IS NULL"
            echo "    Assigned M365 seat $SEAT_ID to user $USER_ID"
        else
            echo "    WARNING: No free M365 seat available for user $USER_ID"
        fi
    fi
done

echo "  M365 seats assigned to alee, bkumar, dmiller, fsingh, gpark."
echo "  ezhang intentionally has NO M365 seat."

# ---------------------------------------------------------------
# 7. Record baseline state for verification
# ---------------------------------------------------------------
echo "  Recording baseline state..."

# Save user IDs
echo "$ALEE_ID" > /tmp/recon_alee_id.txt
echo "$BKUMAR_ID" > /tmp/recon_bkumar_id.txt
echo "$DMILLER_ID" > /tmp/recon_dmiller_id.txt
echo "$EZHANG_ID" > /tmp/recon_ezhang_id.txt
echo "$FSINGH_ID" > /tmp/recon_fsingh_id.txt
echo "$GPARK_ID" > /tmp/recon_gpark_id.txt

# Save asset IDs
echo "$RECON_L001_ID" > /tmp/recon_l001_id.txt
echo "$RECON_MONA_ID" > /tmp/recon_mona_id.txt
echo "$RECON_L002_ID" > /tmp/recon_l002_id.txt
echo "$RECON_L003_ID" > /tmp/recon_l003_id.txt
echo "$RECON_L004_ID" > /tmp/recon_l004_id.txt
echo "$RECON_L005_ID" > /tmp/recon_l005_id.txt
echo "$RECON_L006_ID" > /tmp/recon_l006_id.txt
echo "$RECON_S001_ID" > /tmp/recon_s001_id.txt
echo "$RECON_S002_ID" > /tmp/recon_s002_id.txt
echo "$RECON_D001_ID" > /tmp/recon_d001_id.txt
echo "$RECON_MONB_ID" > /tmp/recon_monb_id.txt

# Save license ID
echo "$MS365_ID" > /tmp/recon_ms365_id.txt

# Record ppatel baseline location
PPATEL_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='ppatel' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
PPATEL_LOC=$(snipeit_db_query "SELECT location_id FROM users WHERE id=$PPATEL_ID AND deleted_at IS NULL" | tr -d '[:space:]')
echo "$PPATEL_ID" > /tmp/recon_ppatel_id.txt
echo "$PPATEL_LOC" > /tmp/recon_ppatel_orig_loc.txt

# Record Marketing department baseline
echo "$DEPT_MARKETING" > /tmp/recon_dept_marketing_id.txt

# Record status label IDs
echo "$SL_READY_ID" > /tmp/recon_sl_ready_id.txt
echo "$SL_REPAIR_ID" > /tmp/recon_sl_repair_id.txt

# Record baseline for collateral damage check
snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag NOT LIKE 'RECON-%' AND deleted_at IS NULL" | tr -d '[:space:]' > /tmp/recon_other_asset_count.txt
snipeit_db_query "SELECT COUNT(*) FROM users WHERE username NOT IN ('alee','bkumar','dmiller','ezhang','fsingh','gpark','mrivera','ytanaka') AND deleted_at IS NULL" | tr -d '[:space:]' > /tmp/recon_other_user_count.txt

# Record timestamp
date +%s > /tmp/recon_task_start.txt

# ---------------------------------------------------------------
# 8. Ensure Firefox is running and on Snipe-IT dashboard
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/recon_initial.png

echo "=== end_of_quarter_it_reconciliation task setup complete ==="
echo "Task: End-of-quarter IT reconciliation — offboarding, onboarding, warranty audit, org update"
echo "  Departing: alee (2 assets), bkumar (1 asset)"
echo "  Warranty expired: RECON-L003 (dmiller), RECON-L004 (ezhang)"
echo "  Active warranty: RECON-L005 (fsingh), RECON-L006 (gpark)"
echo "  Distractors: RECON-D001 (desktop, dmiller), RECON-MON-B (monitor, unassigned)"
echo "  Spares: RECON-S001, RECON-S002 (Ready to Deploy)"
echo "  M365 seats: alee, bkumar, dmiller, fsingh, gpark (ezhang missing)"
