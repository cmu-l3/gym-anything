#!/bin/bash
set -e
echo "=== Setting up building_commissioning_data_entry ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Discover class names
building_cls = find_class(r"^Building$", token) or "Building"
floor_cls = find_class(r"^Floor$", token) or "Floor"
room_cls = find_class(r"^Room$", token) or "Room"

# Discover asset/equipment class
asset_cls = None
for pattern in [r"^CI$", r"^Asset$", r"InternalEquipment", r"Equipment",
                r"NetworkDevice", r"TechnicalAsset", r"^Device$"]:
    found = find_class(pattern, token)
    if found:
        asset_cls = found
        break
if not asset_cls:
    for candidate in ["CI", "Asset", "InternalEquipment", "Equipment"]:
        resp = api("GET", f"classes/{candidate}/cards?limit=1", token)
        if resp is not None:
            asset_cls = candidate
            break

print(f"Classes: building={building_cls}, floor={floor_cls}, room={room_cls}, asset={asset_cls}")

# Get attributes for each class
building_attrs = {a.get("_id", ""): a for a in get_class_attributes(building_cls, token)}
floor_attrs = {a.get("_id", ""): a for a in get_class_attributes(floor_cls, token)}
room_attrs = {a.get("_id", ""): a for a in get_class_attributes(room_cls, token)}
asset_attrs = {a.get("_id", ""): a for a in get_class_attributes(asset_cls, token)} if asset_cls else {}

print(f"Building attrs: {list(building_attrs.keys())[:20]}")
print(f"Floor attrs: {list(floor_attrs.keys())[:20]}")
print(f"Room attrs: {list(room_attrs.keys())[:20]}")
print(f"Asset attrs: {list(asset_attrs.keys())[:20]}")

# Find key field names
def find_field(attr_map, keywords):
    for aname in attr_map:
        alow = aname.lower()
        if any(kw in alow for kw in keywords):
            return aname
    return None

floor_building_field = find_field(floor_attrs, ["building", "parent", "location"])
room_floor_field = find_field(room_attrs, ["floor", "parent", "level"])
asset_building_field = find_field(asset_attrs, ["building", "location", "site"])
asset_serial_field = find_field(asset_attrs, ["serial"])
building_address_field = find_field(building_attrs, ["address", "street"])

print(f"Floor->Building field: {floor_building_field}")
print(f"Room->Floor field: {room_floor_field}")
print(f"Asset->Building field: {asset_building_field}")
print(f"Asset serial field: {asset_serial_field}")
print(f"Building address field: {building_address_field}")

# Record baselines
baseline_buildings = count_cards(building_cls, token)
baseline_floors = count_cards(floor_cls, token)
baseline_rooms = count_cards(room_cls, token)
baseline_assets = count_cards(asset_cls, token) if asset_cls else 0

existing_building_ids = [b.get("_id") for b in get_cards(building_cls, token, limit=100)]
existing_floor_ids = [f.get("_id") for f in get_cards(floor_cls, token, limit=200)]
existing_room_ids = [r.get("_id") for r in get_cards(room_cls, token, limit=500)]
existing_asset_ids = [a.get("_id") for a in get_cards(asset_cls, token, limit=500)] if asset_cls else []

print(f"Baselines: buildings={baseline_buildings}, floors={baseline_floors}, "
      f"rooms={baseline_rooms}, assets={baseline_assets}")

baseline = {
    "building_cls": building_cls,
    "floor_cls": floor_cls,
    "room_cls": room_cls,
    "asset_cls": asset_cls,
    "floor_building_field": floor_building_field,
    "room_floor_field": room_floor_field,
    "asset_building_field": asset_building_field,
    "asset_serial_field": asset_serial_field,
    "building_address_field": building_address_field,
    "baseline_buildings": baseline_buildings,
    "baseline_floors": baseline_floors,
    "baseline_rooms": baseline_rooms,
    "baseline_assets": baseline_assets,
    "existing_building_ids": existing_building_ids,
    "existing_floor_ids": existing_floor_ids,
    "existing_room_ids": existing_room_ids,
    "existing_asset_ids": existing_asset_ids,
    "expected_building_code": "BLD-WESTPARK",
    "expected_floor_codes": ["FLR-WP-G", "FLR-WP-1", "FLR-WP-2", "FLR-WP-3"],
    "expected_room_codes": [
        "RM-WP-G01", "RM-WP-G02", "RM-WP-G03",
        "RM-WP-101", "RM-WP-102", "RM-WP-103",
        "RM-WP-201", "RM-WP-202", "RM-WP-203",
        "RM-WP-301", "RM-WP-302", "RM-WP-303",
    ],
    "expected_room_floors": {
        "RM-WP-G01": "FLR-WP-G", "RM-WP-G02": "FLR-WP-G", "RM-WP-G03": "FLR-WP-G",
        "RM-WP-101": "FLR-WP-1", "RM-WP-102": "FLR-WP-1", "RM-WP-103": "FLR-WP-1",
        "RM-WP-201": "FLR-WP-2", "RM-WP-202": "FLR-WP-2", "RM-WP-203": "FLR-WP-2",
        "RM-WP-301": "FLR-WP-3", "RM-WP-302": "FLR-WP-3", "RM-WP-303": "FLR-WP-3",
    },
    "expected_asset_codes": [
        "AST-WP-HVAC-01", "AST-WP-HVAC-02", "AST-WP-ELEC-01",
        "AST-WP-ELEV-01", "AST-WP-FIRE-01", "AST-WP-GEN-01",
    ],
    "expected_asset_serials": {
        "AST-WP-HVAC-01": "SN-TRANE-2025-RTU-4400",
        "AST-WP-HVAC-02": "SN-CARRIER-2025-AHU-7821",
        "AST-WP-ELEC-01": "SN-EATON-2024-MDP-1560",
        "AST-WP-ELEV-01": "SN-OTIS-2025-GEN2-3391",
        "AST-WP-FIRE-01": "SN-SIMPLEX-2025-4100U-0887",
        "AST-WP-GEN-01": "SN-CUMMINS-2025-QSB-6244",
    },
}
save_baseline("/tmp/bcd_baseline.json", baseline)
print("Baseline saved")
PYEOF

# Create commissioning report on desktop
cat > /home/ga/Desktop/commissioning_report.txt << 'REPORT'
================================================================
     BUILDING COMMISSIONING REPORT — WESTPARK OFFICE TOWER
================================================================
Date: 2026-03-01
Prepared by: Henderson & Associates Building Consultants
Project: Westpark Drive Acquisition — Asset Onboarding

================================================================
SECTION 1: BUILDING INFORMATION
================================================================
Code:        BLD-WESTPARK
Description: Westpark Office Tower
Address:     2750 Westpark Drive, Houston, TX 77042
Type:        Commercial Office — Class A
Year Built:  2019
Gross Area:  48,000 sq ft (4 floors above grade)

================================================================
SECTION 2: FLOOR REGISTRY
================================================================
Code        | Description              | Level
------------|--------------------------|-------
FLR-WP-G   | Ground Floor (Lobby)     | 0
FLR-WP-1   | First Floor (Office)     | 1
FLR-WP-2   | Second Floor (Office)    | 2
FLR-WP-3   | Third Floor (Executive)  | 3

All floors belong to building BLD-WESTPARK.

================================================================
SECTION 3: ROOM REGISTRY
================================================================
Code        | Description                    | Floor     | Type
------------|--------------------------------|-----------|----------
RM-WP-G01  | Main Lobby                     | FLR-WP-G  | Lobby
RM-WP-G02  | Security Office                | FLR-WP-G  | Office
RM-WP-G03  | Ground Floor Restroom          | FLR-WP-G  | Bathroom
RM-WP-101  | Open Office Area 1A            | FLR-WP-1  | Office
RM-WP-102  | Conference Room 1B             | FLR-WP-1  | Conference
RM-WP-103  | First Floor Utility Closet     | FLR-WP-1  | Utility
RM-WP-201  | Open Office Area 2A            | FLR-WP-2  | Office
RM-WP-202  | Conference Room 2B             | FLR-WP-2  | Conference
RM-WP-203  | Server Room                    | FLR-WP-2  | Utility
RM-WP-301  | Executive Suite                | FLR-WP-3  | Office
RM-WP-302  | Board Room                     | FLR-WP-3  | Conference
RM-WP-303  | Executive Restroom             | FLR-WP-3  | Bathroom

Each room must be linked to its corresponding floor record.

================================================================
SECTION 4: INFRASTRUCTURE ASSETS
================================================================
Code            | Description                        | Serial Number                  | Location
----------------|------------------------------------|--------------------------------|----------
AST-WP-HVAC-01 | Trane Rooftop Unit RTU-400        | SN-TRANE-2025-RTU-4400         | Rooftop
AST-WP-HVAC-02 | Carrier Air Handler AHU-200       | SN-CARRIER-2025-AHU-7821       | Mechanical Rm
AST-WP-ELEC-01 | Eaton Main Distribution Panel     | SN-EATON-2024-MDP-1560         | Electrical Rm
AST-WP-ELEV-01 | Otis Gen2 Passenger Elevator      | SN-OTIS-2025-GEN2-3391         | Elevator Shaft
AST-WP-FIRE-01 | Simplex 4100U Fire Alarm Panel    | SN-SIMPLEX-2025-4100U-0887     | Lobby
AST-WP-GEN-01  | Cummins QSB7 Emergency Generator  | SN-CUMMINS-2025-QSB-6244       | Generator Yard

All assets must be associated with building BLD-WESTPARK.
Serial numbers must be entered exactly as shown.

================================================================
SECTION 5: INSTRUCTIONS
================================================================
Enter all data above into OpenMaint. Ensure:
- Building is created FIRST (floors reference it)
- Floors created BEFORE rooms (rooms reference floors)
- Assets reference the building
- Do NOT modify existing buildings, floors, rooms, or assets
================================================================
REPORT

chown ga:ga /home/ga/Desktop/commissioning_report.txt

date +%s > /tmp/bcd_start_ts

# Restart browser
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task_bcd.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi
focus_firefox || true
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --delay 20 '$OPENMAINT_URL'"
su - ga -c "DISPLAY=:1 xdotool key Return"

if ! wait_for_rendered_browser_view /tmp/bcd_start_screenshot.png 60; then
    echo "WARNING: Browser view did not stabilize"
fi

echo "=== building_commissioning_data_entry setup complete ==="
