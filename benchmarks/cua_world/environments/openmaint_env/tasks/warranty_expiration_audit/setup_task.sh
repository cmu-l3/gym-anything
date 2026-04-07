#!/bin/bash
set -e
echo "=== Setting up warranty_expiration_audit ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the audit report on the desktop
cat > /home/ga/Desktop/warranty_audit_report.txt << 'EOF'
QUARTERLY WARRANTY AUDIT REPORT — Q1 2026
Prepared by: Procurement Department
Date: 2026-01-15
=============================================

SECTION A: WARRANTY RENEWAL REQUIRED (Update CMMS notes)
---------------------------------------------------------
1. WAR-HVAC-001 — Rooftop HVAC Unit #1
   Current warranty expires: 2026-03-01
   Renewal approved through: 2027-03-01
   Vendor: Carrier Commercial
   ACTION: Update notes with "WARRANTY RENEWED through 2027-03-01 — Carrier Commercial"

2. WAR-HVAC-002 — Rooftop HVAC Unit #2
   Current warranty expires: 2026-04-15
   Renewal approved through: 2027-04-15
   Vendor: Carrier Commercial
   ACTION: Update notes with "WARRANTY RENEWED through 2027-04-15 — Carrier Commercial"

3. WAR-ELEV-001 — Passenger Elevator Main Drive
   Current warranty expires: 2026-02-28
   Renewal approved through: 2028-02-28
   Vendor: Otis Elevator Co.
   ACTION: Update notes with "WARRANTY RENEWED through 2028-02-28 — Otis Elevator Co."

SECTION B: PRE-EXPIRATION MAINTENANCE REQUIRED (Create Work Order)
------------------------------------------------------------------
4. WAR-GEN-001 — Emergency Generator #1
   Warranty expires: 2026-06-30
   Required inspection: Full load bank test and oil analysis before warranty expires
   Priority: High
   ACTION: Create work order "Pre-warranty inspection: WAR-GEN-001 — Full load bank test and oil analysis required before 2026-06-30 warranty expiration"

5. WAR-ELEC-003 — Main Electrical Switchgear
   Warranty expires: 2026-05-15
   Required inspection: Thermal imaging scan and contact resistance test
   Priority: High
   ACTION: Create work order "Pre-warranty inspection: WAR-ELEC-003 — Thermal imaging scan and contact resistance test required before 2026-05-15 warranty expiration"

SECTION C: OUT OF WARRANTY
--------------------------
6. WAR-ELEC-001 — UPS Battery Bank A
   Warranty expired: 2025-12-31
   No renewal available (discontinued model)
   ACTION: Update notes with "OUT OF WARRANTY as of 2025-12-31 — No renewal available (discontinued model)"

SECTION D: NO ACTION NEEDED
----------------------------
7. WAR-PUMP-002 — Chilled Water Circulation Pump
   Status: WARRANTY ALREADY RENEWED externally by vendor maintenance agreement
   Current warranty valid through: 2028-12-31
   *** DO NOT MODIFY THIS RECORD — warranty was renewed through vendor
       maintenance agreement and CMMS record is already correct ***
EOF
chown ga:ga /home/ga/Desktop/warranty_audit_report.txt

# Seed data via Python API
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Find Asset/CI class
asset_cls = None
# Try specific class names often found in OpenMaint/CMDBuild demos
candidates = ["Asset", "Equipment", "CI", "InternalEquipment", "Device", "TechnicalAsset"]
for c in candidates:
    if find_class(f"^{c}$", token):
        asset_cls = c
        break
# Fallback search
if not asset_cls:
    for c in list_classes(token):
        if "asset" in c.get("description", "").lower():
            asset_cls = c.get("_id")
            break

print(f"Using Asset Class: {asset_cls}")

# 2. Find Work Order class (for baseline recording)
wo_type, wo_cls = find_maintenance_class(token)
print(f"Work Order Class: {wo_cls} (type={wo_type})")

# 3. Seed Assets
# We need to ensure we don't duplicate if they already exist from a previous run (though env is usually fresh)
# But we'll create unique codes just in case.

seeded_assets = [
    {"Code": "WAR-HVAC-001", "Description": "Rooftop HVAC Unit #1", "Notes": "Warranty: Carrier Commercial, expires 2026-03-01"},
    {"Code": "WAR-HVAC-002", "Description": "Rooftop HVAC Unit #2", "Notes": "Warranty: Carrier Commercial, expires 2026-04-15"},
    {"Code": "WAR-ELEV-001", "Description": "Passenger Elevator Main Drive", "Notes": "Warranty: Otis Elevator Co., expires 2026-02-28"},
    {"Code": "WAR-GEN-001", "Description": "Emergency Generator #1", "Notes": "Warranty: Generac Power, expires 2026-06-30"},
    {"Code": "WAR-ELEC-001", "Description": "UPS Battery Bank A", "Notes": "Warranty: Eaton Corporation, expires 2025-12-31"},
    {"Code": "WAR-ELEC-003", "Description": "Main Electrical Switchgear", "Notes": "Warranty: Schneider Electric, expires 2026-05-15"},
    {"Code": "WAR-PUMP-002", "Description": "Chilled Water Circulation Pump", "Notes": "WARRANTY RENEWED through 2028-12-31 — Vendor maintenance agreement"}
]

asset_ids = {}

# Get class attributes to find correct fields
attrs = get_class_attributes(asset_cls, token) if asset_cls else []
attr_map = {a.get("_id", "").lower(): a.get("_id") for a in attrs}

# Determine field mapping
desc_field = attr_map.get("description", "Description")
notes_field = attr_map.get("notes", "Notes")
if "notes" not in attr_map:
    # Fallback: sometimes Comment or Remark
    notes_field = attr_map.get("comment", attr_map.get("remark", desc_field))

print(f"Mapping: Description -> {desc_field}, Notes -> {notes_field}")

for item in seeded_assets:
    # Check if exists
    existing = get_cards(asset_cls, token, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":\"{item['Code']}\"}}}}}}")
    if existing:
        print(f"Asset {item['Code']} exists, updating...")
        card_id = existing[0]["_id"]
        # Reset state
        update_data = {desc_field: item["Description"]}
        if notes_field != desc_field:
            update_data[notes_field] = item["Notes"]
        else:
            # If no separate notes field, append to description
            update_data[desc_field] = f"{item['Description']} - {item['Notes']}"
        
        update_card(asset_cls, card_id, update_data, token)
        asset_ids[item["Code"]] = card_id
    else:
        print(f"Creating {item['Code']}...")
        create_data = {"Code": item["Code"], desc_field: item["Description"]}
        if notes_field != desc_field:
            create_data[notes_field] = item["Notes"]
        else:
            create_data[desc_field] = f"{item['Description']} - {item['Notes']}"
            
        card_id = create_card(asset_cls, create_data, token)
        asset_ids[item["Code"]] = card_id

# 4. Record Baseline
baseline = {
    "asset_cls": asset_cls,
    "wo_type": wo_type,
    "wo_cls": wo_cls,
    "asset_ids": asset_ids,
    "desc_field": desc_field,
    "notes_field": notes_field,
    # Record initial state of contamination asset
    "contam_initial": {
        "Code": "WAR-PUMP-002",
        "Notes": seeded_assets[6]["Notes"]
    }
}

save_baseline("/tmp/war_baseline.json", baseline)
print("Baseline saved.")

PYEOF

# Start Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|openmaint"; then
        break
    fi
    sleep 1
done

# Focus and Maximize
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="