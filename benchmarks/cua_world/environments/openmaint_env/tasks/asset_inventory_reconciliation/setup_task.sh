#!/bin/bash
set -e
echo "=== Setting up asset_inventory_reconciliation ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

python3 << 'PYEOF'
import sys, json, os, random
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Discover asset/CI class
asset_cls = None
for pattern in [r"^CI$", r"^Asset$", r"InternalEquipment", r"Equipment",
                r"NetworkDevice", r"^Device$", r"TechnicalAsset"]:
    found = find_class(pattern, token)
    if found:
        asset_cls = found
        break

if not asset_cls:
    all_cls = list_classes(token)
    for c in all_cls:
        name = c.get("_id", "")
        desc = c.get("description", "").lower()
        if any(kw in desc for kw in ["asset", "equipment", "configuration item", "ci"]):
            asset_cls = name
            break

# Try common class names
if not asset_cls:
    for candidate in ["CI", "Asset", "InternalEquipment", "Equipment",
                      "NetworkDevice", "Server", "Desktop", "Printer"]:
        resp = api("GET", f"classes/{candidate}/cards?limit=1", token)
        if resp is not None:
            asset_cls = candidate
            break

print(f"Asset class: {asset_cls}")

# Get asset class attributes
attrs = get_class_attributes(asset_cls, token) if asset_cls else []
attr_map = {a.get("_id", ""): a for a in attrs}
print(f"Asset attributes: {list(attr_map.keys())[:30]}")

# Discover field names
serial_field = None
building_field = None
floor_field = None
room_field = None
status_field = None
brand_field = None
model_field = None

for aname, ainfo in attr_map.items():
    alow = aname.lower()
    adesc = (ainfo.get("description", "") or "").lower()
    if "serial" in alow or "serial" in adesc:
        if not serial_field: serial_field = aname
    if "building" in alow or ("location" in alow and "floor" not in alow):
        if not building_field: building_field = aname
    if "floor" in alow or "level" in alow:
        if not floor_field: floor_field = aname
    if "room" in alow or "space" in alow:
        if not room_field: room_field = aname
    if "status" in alow and "flow" not in alow:
        if not status_field: status_field = aname
    if "brand" in alow or "manufacturer" in alow:
        if not brand_field: brand_field = aname
    if "model" in alow:
        if not model_field: model_field = aname

# Default serial field
if not serial_field:
    serial_field = "SerialNumber"

print(f"Fields: serial={serial_field}, building={building_field}, "
      f"floor={floor_field}, room={room_field}, status={status_field}")

# Get buildings
buildings = get_buildings(token)
bld_info = []
for b in buildings[:3]:
    bld_info.append({"id": b.get("_id"), "code": b.get("Code", ""), "desc": b.get("Description", "")})

# Create 4 assets with WRONG serial numbers (to be corrected)
wrong_serials = [
    {"Code": "SN-FIX-001", "Description": "Portable X-Ray Unit - Radiology Dept",
     "wrong_serial": "SN-9999-WRONG", "correct_serial": "SN-2024-PXR-0471"},
    {"Code": "SN-FIX-002", "Description": "Autoclave Sterilizer - Central Supply",
     "wrong_serial": "SN-8888-WRONG", "correct_serial": "SN-2023-ACS-1182"},
    {"Code": "SN-FIX-003", "Description": "Patient Monitor - ICU",
     "wrong_serial": "SN-7777-WRONG", "correct_serial": "SN-2024-PMN-0693"},
    {"Code": "SN-FIX-004", "Description": "Infusion Pump - Oncology",
     "wrong_serial": "SN-6666-WRONG", "correct_serial": "SN-2023-IFP-2205"},
]

serial_fix_ids = {}
for item in wrong_serials:
    card_data = {
        "Code": item["Code"],
        "Description": item["Description"],
    }
    if serial_field:
        card_data[serial_field] = item["wrong_serial"]
    if building_field and bld_info:
        card_data[building_field] = bld_info[0]["id"]
    cid = create_card(asset_cls, card_data, token)
    serial_fix_ids[item["Code"]] = cid
    print(f"Created asset {item['Code']}: id={cid}")

# Create 2 assets to be DECOMMISSIONED
decom_assets = [
    {"Code": "DECOM-001", "Description": "Old CRT Monitor - Storage Room B2",
     "serial": "SN-2015-CRT-0001"},
    {"Code": "DECOM-002", "Description": "Broken Wheelchair - Lobby Storage",
     "serial": "SN-2017-WCH-0044"},
]

decom_ids = {}
for item in decom_assets:
    card_data = {
        "Code": item["Code"],
        "Description": item["Description"],
    }
    if serial_field:
        card_data[serial_field] = item["serial"]
    if building_field and bld_info:
        card_data[building_field] = bld_info[0]["id"]
    cid = create_card(asset_cls, card_data, token)
    decom_ids[item["Code"]] = cid
    print(f"Created decom asset {item['Code']}: id={cid}")

# Create CONTAMINATION asset (looks like decom but is a valid transfer)
contam_data = {
    "Code": "DECOM-003",
    "Description": "Portable Ultrasound Unit - Recently transferred from East Wing",
}
if serial_field:
    contam_data[serial_field] = "SN-2024-PUS-0887"
if building_field and len(bld_info) > 1:
    contam_data[building_field] = bld_info[1]["id"]
contam_id = create_card(asset_cls, contam_data, token)
print(f"Created contamination asset DECOM-003: id={contam_id}")

# Create 2 assets with WRONG locations (to be corrected)
wrong_loc_assets = [
    {"Code": "LOC-FIX-001", "Description": "Defibrillator AED - Emergency Dept",
     "serial": "SN-2023-AED-0156",
     "wrong_building_idx": 0, "correct_building_idx": 1},
    {"Code": "LOC-FIX-002", "Description": "Ventilator Unit - Respiratory Therapy",
     "serial": "SN-2024-VNT-0332",
     "wrong_building_idx": 1, "correct_building_idx": 2 if len(bld_info) > 2 else 0},
]

loc_fix_ids = {}
for item in wrong_loc_assets:
    card_data = {
        "Code": item["Code"],
        "Description": item["Description"],
    }
    if serial_field:
        card_data[serial_field] = item["serial"]
    if building_field and bld_info:
        card_data[building_field] = bld_info[item["wrong_building_idx"]]["id"]
    cid = create_card(asset_cls, card_data, token)
    loc_fix_ids[item["Code"]] = cid
    print(f"Created wrong-location asset {item['Code']}: id={cid}")

# Record baseline
baseline_count = count_cards(asset_cls, token) if asset_cls else 0
existing_assets = get_cards(asset_cls, token, limit=1000)
existing_ids = [a.get("_id") for a in existing_assets]

baseline = {
    "asset_class": asset_cls,
    "serial_field": serial_field,
    "building_field": building_field,
    "floor_field": floor_field,
    "room_field": room_field,
    "status_field": status_field,
    "buildings": bld_info,
    "baseline_count": baseline_count,
    "all_seeded_ids": list(serial_fix_ids.values()) + list(decom_ids.values()) + [contam_id] + list(loc_fix_ids.values()),
    "serial_fix_ids": serial_fix_ids,
    "serial_corrections": {item["Code"]: item["correct_serial"] for item in wrong_serials},
    "decom_ids": decom_ids,
    "contam_id": contam_id,
    "loc_fix_ids": loc_fix_ids,
    "loc_corrections": {item["Code"]: {
        "correct_building_idx": item["correct_building_idx"],
        "correct_building_id": bld_info[item["correct_building_idx"]]["id"] if item["correct_building_idx"] < len(bld_info) else None,
    } for item in wrong_loc_assets},
    "new_asset_codes": ["NEW-AUD-001", "NEW-AUD-002", "NEW-AUD-003"],
}
save_baseline("/tmp/air_baseline.json", baseline)
print("Baseline saved")

# Generate the audit report CSV on the desktop
bld_names = [b.get("desc", b.get("code", "Building")) for b in bld_info]
csv_lines = [
    "Action,Code,Description,SerialNumber,Building,Status,Notes",
    f'UPDATE_SERIAL,SN-FIX-001,Portable X-Ray Unit - Radiology Dept,SN-2024-PXR-0471,{bld_names[0] if bld_names else "Building A"},Active,Physical label reads SN-2024-PXR-0471',
    f'UPDATE_SERIAL,SN-FIX-002,Autoclave Sterilizer - Central Supply,SN-2023-ACS-1182,{bld_names[0] if bld_names else "Building A"},Active,Physical label reads SN-2023-ACS-1182',
    f'UPDATE_SERIAL,SN-FIX-003,Patient Monitor - ICU,SN-2024-PMN-0693,{bld_names[0] if bld_names else "Building A"},Active,Physical label reads SN-2024-PMN-0693',
    f'UPDATE_SERIAL,SN-FIX-004,Infusion Pump - Oncology,SN-2023-IFP-2205,{bld_names[0] if bld_names else "Building A"},Active,Physical label reads SN-2023-IFP-2205',
    f'DECOMMISSION,DECOM-001,Old CRT Monitor - Storage Room B2,SN-2015-CRT-0001,{bld_names[0] if bld_names else "Building A"},Removed,Physically removed during Q2 renovation',
    f'DECOMMISSION,DECOM-002,Broken Wheelchair - Lobby Storage,SN-2017-WCH-0044,{bld_names[0] if bld_names else "Building A"},Removed,Disposed per facilities directive FD-2025-118',
    f'DO_NOT_DECOMMISSION,DECOM-003,Portable Ultrasound Unit,SN-2024-PUS-0887,{bld_names[1] if len(bld_names)>1 else "Building B"},Active,TRANSFER from East Wing arrived 2026-02-28 - DO NOT DECOMMISSION',
    f'ADD_NEW,NEW-AUD-001,Surgical Light LED - Operating Room 3,SN-2026-SLT-0012,{bld_names[0] if bld_names else "Building A"},Active,Installed during Q4 2025 OR upgrade',
    f'ADD_NEW,NEW-AUD-002,Blood Gas Analyzer - Emergency Lab,SN-2026-BGA-0003,{bld_names[1] if len(bld_names)>1 else "Building B"},Active,New acquisition per PO-2026-0441',
    f'ADD_NEW,NEW-AUD-003,Nurse Call Panel - Ward 7 Station,SN-2026-NCP-0019,{bld_names[2] if len(bld_names)>2 else "Building C"},Active,Installed during Ward 7 renovation',
    f'CORRECT_LOCATION,LOC-FIX-001,Defibrillator AED - Emergency Dept,SN-2023-AED-0156,{bld_names[1] if len(bld_names)>1 else "Building B"},Active,Physically located in {bld_names[1] if len(bld_names)>1 else "Building B"} not {bld_names[0] if bld_names else "Building A"}',
    f'CORRECT_LOCATION,LOC-FIX-002,Ventilator Unit - Respiratory Therapy,SN-2024-VNT-0332,{bld_names[2] if len(bld_names)>2 else "Building C"},Active,Physically located in {bld_names[2] if len(bld_names)>2 else "Building C"} not {bld_names[1] if len(bld_names)>1 else "Building B"}',
]

with open("/home/ga/Desktop/audit_report.csv", "w") as f:
    f.write("\n".join(csv_lines) + "\n")
os.chmod("/home/ga/Desktop/audit_report.csv", 0o666)
print("Audit report CSV created")
PYEOF

date +%s > /tmp/air_start_ts

# Restart browser
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task_air.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi
focus_firefox || true
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --delay 20 '$OPENMAINT_URL'"
su - ga -c "DISPLAY=:1 xdotool key Return"

if ! wait_for_rendered_browser_view /tmp/air_start_screenshot.png 60; then
    echo "WARNING: Browser view did not stabilize"
fi

echo "=== asset_inventory_reconciliation setup complete ==="
