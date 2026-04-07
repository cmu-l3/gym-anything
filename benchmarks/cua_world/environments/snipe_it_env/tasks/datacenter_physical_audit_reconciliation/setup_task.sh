#!/bin/bash
echo "=== Setting up datacenter_physical_audit_reconciliation task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure required IDs exist safely via APIs and DB Queries
# Locations
LOC_A_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='Datacenter - Rack A' LIMIT 1" | tr -d '[:space:]')
if [ -z "$LOC_A_ID" ]; then
    LOC_A_RES=$(snipeit_api POST "locations" '{"name":"Datacenter - Rack A","currency":"USD"}')
    LOC_A_ID=$(echo "$LOC_A_RES" | jq -r '.payload.id // .id // empty')
fi

LOC_B_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='Datacenter - Rack B' LIMIT 1" | tr -d '[:space:]')
if [ -z "$LOC_B_ID" ]; then
    LOC_B_RES=$(snipeit_api POST "locations" '{"name":"Datacenter - Rack B","currency":"USD"}')
    LOC_B_ID=$(echo "$LOC_B_RES" | jq -r '.payload.id // .id // empty')
fi

# Fallbacks in case API fails
if [ -z "$LOC_A_ID" ]; then LOC_A_ID=1; fi
if [ -z "$LOC_B_ID" ]; then LOC_B_ID=2; fi

# Status Labels
SL_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')
if [ -z "$SL_DEPLOYED" ]; then
    SL_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE type='deployable' LIMIT 1" | tr -d '[:space:]')
fi
if [ -z "$SL_DEPLOYED" ]; then SL_DEPLOYED=1; fi

# Models
MOD_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='1U Rack Server' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MOD_ID" ]; then
    CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Servers' LIMIT 1" | tr -d '[:space:]')
    if [ -z "$CAT_ID" ]; then
        CAT_RES=$(snipeit_api POST "categories" '{"name":"Servers","category_type":"asset"}')
        CAT_ID=$(echo "$CAT_RES" | jq -r '.payload.id // .id // empty')
    fi
    if [ -z "$CAT_ID" ]; then CAT_ID=1; fi
    
    MAN_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Generic' LIMIT 1" | tr -d '[:space:]')
    if [ -z "$MAN_ID" ]; then
        MAN_RES=$(snipeit_api POST "manufacturers" '{"name":"Generic"}')
        MAN_ID=$(echo "$MAN_RES" | jq -r '.payload.id // .id // empty')
    fi
    if [ -z "$MAN_ID" ]; then MAN_ID=1; fi
    
    MOD_RES=$(snipeit_api POST "models" "{\"name\":\"1U Rack Server\",\"category_id\":$CAT_ID,\"manufacturer_id\":$MAN_ID}")
    MOD_ID=$(echo "$MOD_RES" | jq -r '.payload.id // .id // empty')
fi
if [ -z "$MOD_ID" ]; then MOD_ID=1; fi

# 2. Inject Target Assets
echo "Injecting target assets..."
for tag in SRV-RACKA-01 SRV-RACKA-02 SRV-RACKA-03 SRV-RACKA-04 SRV-RACKB-99; do
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'" 2>/dev/null || true
done

snipeit_api POST "hardware" "{\"asset_tag\":\"SRV-RACKA-01\",\"name\":\"Database Server 1\",\"model_id\":$MOD_ID,\"status_id\":$SL_DEPLOYED,\"rtd_location_id\":$LOC_A_ID}"
snipeit_api POST "hardware" "{\"asset_tag\":\"SRV-RACKA-02\",\"name\":\"Database Server 2\",\"model_id\":$MOD_ID,\"status_id\":$SL_DEPLOYED,\"rtd_location_id\":$LOC_A_ID}"
snipeit_api POST "hardware" "{\"asset_tag\":\"SRV-RACKA-03\",\"name\":\"App Server 1\",\"model_id\":$MOD_ID,\"status_id\":$SL_DEPLOYED,\"rtd_location_id\":$LOC_A_ID}"
snipeit_api POST "hardware" "{\"asset_tag\":\"SRV-RACKA-04\",\"name\":\"App Server 2\",\"model_id\":$MOD_ID,\"status_id\":$SL_DEPLOYED,\"rtd_location_id\":$LOC_A_ID}"
snipeit_api POST "hardware" "{\"asset_tag\":\"SRV-RACKB-99\",\"name\":\"Web Server 99\",\"model_id\":$MOD_ID,\"status_id\":$SL_DEPLOYED,\"rtd_location_id\":$LOC_B_ID}"

# 3. Record baseline audits
INITIAL_AUDITS=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE action_type='audit'" | tr -d '[:space:]')
echo "$INITIAL_AUDITS" > /tmp/initial_audit_count.txt

# 4. Create Audit Notes file
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/audit_notes_rack_a.txt << 'EOF'
AUDIT LOG - Q1 2026
Location: Datacenter - Rack A
Date: 2026-03-08
Auditor: J. Doe

Physical servers found in Rack A:
- SRV-RACKA-01
- SRV-RACKA-02
- SRV-RACKA-03
- SRV-RACKB-99 (Note: This has a Rack B tag but is physically mounted in Rack A)
EOF
chown ga:ga /home/ga/Desktop/audit_notes_rack_a.txt

# 5. UI Setup
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/datacenter_audit_initial.png

echo "=== setup complete ==="