#!/bin/bash
set -e
echo "=== Setting up service_contract_equipment_linkage ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the spec file on desktop
cat > /home/ga/Desktop/contract_specifications.txt << 'EOF'
================================================================
ANNUAL MAINTENANCE CONTRACT REGISTRATION — FY2025/2026
================================================================
Prepared by: Facilities Planning Department
Date: 2025-06-15
Status: FINAL (approved by VP Operations)

================================================================
CONTRACT 1: HVAC FULL SERVICE AGREEMENT
================================================================
Code:           SVC-2025-HVAC-001
Vendor:         CoolAir Systems
Type:           Preventive + Corrective Maintenance
Start Date:     2025-07-01
End Date:       2026-06-30
Annual Value:   $48,000

Covered Equipment (Create these assets if missing):
  - EQ-CHILLER-010 | Carrier 30XA Chiller | Serial: CR-8842-XA | Building 1
  - EQ-AHU-015     | Trane M-Series AHU   | Serial: TM-5521-MS | Building 2

Description: Annual HVAC preventive and corrective maintenance
covering quarterly filter changes, annual coil cleaning,
refrigerant management, and emergency corrective repairs
with 4-hour response time SLA.

================================================================
CONTRACT 2: ELEVATOR MAINTENANCE AGREEMENT
================================================================
Code:           SVC-2025-ELEV-001
Vendor:         VerticalTech Inc
Type:           Preventive Maintenance + Safety Inspection
Start Date:     2025-07-01
End Date:       2026-06-30
Annual Value:   $36,000

Covered Equipment (Create this asset if missing):
  - EQ-ELEV-007    | Otis Gen2 Passenger Elevator | Serial: OG-3317-G2 | Building 3

Description: Annual elevator inspection and preventive maintenance
including monthly safety checks, quarterly load tests, and
annual state certification inspection.

================================================================
CONTRACT 3: FIRE SAFETY INSPECTION AGREEMENT
================================================================
Code:           SVC-2025-FIRE-001
Vendor:         SafeGuard Fire Services
Type:           Inspection + Certification
Start Date:     2025-07-01
End Date:       2026-06-30
Annual Value:   $18,000

Covered Equipment:
  NOTE: Specific equipment to be identified during first site
  visit. No equipment should be linked to this contract yet.

Description: Quarterly fire safety system inspection and certification
covering all fire suppression, detection, and alarm systems.

================================================================
*** REMOVED FROM SCOPE — DO NOT REGISTER ***
================================================================
The following equipment was included in the draft proposal but
has been REMOVED from final contract scope. The vendor declined
coverage due to the equipment exceeding its rated service life.

  - EQ-BOILER-003  | Weil-McLain 88 Series Boiler
    Reason: Unit is 23 years old (rated life: 15 years).
    Vendor liability assessment: coverage denied.
    Action: DO NOT link to any service contract.
    Separate capital replacement request pending.
================================================================
EOF
chown ga:ga /home/ga/Desktop/contract_specifications.txt

# Run Python setup to seed data and record baseline
python3 << 'PYEOF'
import sys, json, os, random
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Discover Classes
# --------------------
# Find Asset/CI class
asset_cls = None
for pattern in [r"^CI$", r"^Asset$", r"InternalEquipment", r"Equipment", r"Device"]:
    found = find_class(pattern, token)
    if found:
        asset_cls = found
        break
if not asset_cls: asset_cls = "CI" # Fallback

# Find Contract class
contract_cls = None
for pattern in [r"Contract", r"Agreement", r"SupplierContract", r"ServiceContract"]:
    found = find_class(pattern, token)
    if found:
        contract_cls = found
        break
if not contract_cls: contract_cls = "Contract" # Fallback

# Find Building class
building_cls = "Building" # Standard in OpenMaint

print(f"Classes identified: Asset={asset_cls}, Contract={contract_cls}, Building={building_cls}")

# 2. Setup Contamination Asset (EQ-BOILER-003)
# --------------------------------------------
contam_code = "EQ-BOILER-003"
contam_desc = "Weil-McLain 88 Series Boiler"
contam_id = None

# Check if it exists
existing_assets = get_cards(asset_cls, token, limit=1000, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{contam_code}\"]}}}}}}")
if existing_assets:
    print(f"Contamination asset {contam_code} already exists.")
    contam_id = existing_assets[0]["_id"]
else:
    print(f"Creating contamination asset {contam_code}...")
    # Get a building to assign it to (first available)
    buildings = get_buildings(token)
    bld_id = buildings[0]["_id"] if buildings else None
    
    attrs = {
        "Code": contam_code,
        "Description": contam_desc,
        "SerialNumber": "SN-OLD-9999",
        "_is_active": True
    }
    # Try to add building relation if attribute exists
    asset_attrs = get_class_attributes(asset_cls, token)
    for a in asset_attrs:
        if "building" in a.get("name", "").lower():
            attrs[a["name"]] = bld_id
            break
            
    contam_id = create_card(asset_cls, attrs, token)
    print(f"Created {contam_code} with ID {contam_id}")

# 3. Record Baseline
# ------------------
baseline = {
    "asset_class": asset_cls,
    "contract_class": contract_cls,
    "contam_id": contam_id,
    "contam_code": contam_code,
    "initial_contract_count": count_cards(contract_cls, token) if contract_cls else 0,
    "initial_asset_count": count_cards(asset_cls, token) if asset_cls else 0,
    "start_time": int(os.popen("date +%s").read().strip())
}

save_baseline("/tmp/sce_baseline.json", baseline)
print("Baseline saved.")

PYEOF

# Prepare browser
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for browser and maximize
if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi
focus_firefox || true

echo "=== Setup complete ==="