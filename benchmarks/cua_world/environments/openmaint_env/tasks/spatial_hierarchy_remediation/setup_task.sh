#!/bin/bash
set -e
echo "=== Setting up spatial_hierarchy_remediation ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Seed the database with the "messy" hierarchy using Python and CMDBuild API
python3 << 'PYEOF'
import sys, json, os, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Discover Classes
# We need Building, Floor, Room classes. Names might vary slightly in different OpenMaint versions/demos.
building_cls = find_class(r"^Building$", token) or find_class(r"^Buildings$", token)
floor_cls = find_class(r"^Floor$", token) or find_class(r"^Level$", token)
room_cls = find_class(r"^Room$", token) or find_class(r"^Space$", token)

if not (building_cls and floor_cls and room_cls):
    print(f"ERROR: Could not find spatial classes. Got: B={building_cls}, F={floor_cls}, R={room_cls}", file=sys.stderr)
    sys.exit(1)

print(f"Classes found: Building={building_cls}, Floor={floor_cls}, Room={room_cls}")

# 2. Discover Attribute Names (for Reference Fields)
# e.g., Floor needs to link to Building. The attribute might be 'Building', 'Parent', etc.
def find_ref_field(cls, target_cls_name, token):
    attrs = get_class_attributes(cls, token)
    for a in attrs:
        # Check if attribute type is reference (often just implied by name in simple logic, or check type)
        # We'll rely on name matching for this environment setup script
        aname = a.get("_id", "")
        if target_cls_name.lower() in aname.lower():
            return aname
    return target_cls_name # Fallback guess

floor_ref_building = find_ref_field(floor_cls, "Building", token)
room_ref_floor = find_ref_field(room_cls, "Floor", token)

print(f"Reference Fields: Floor->{floor_ref_building}, Room->{room_ref_floor}")

# 3. Create Buildings (with Intentional Errors)
# BLD-NORTH: Wrong Address
# BLD-SOUTH: Wrong Address
# BLD-EAST: Wrong City
buildings_data = [
    {"Code": "BLD-NORTH", "Description": "North Campus Building", "Address": "123 Old Industrial Rd", "City": "Portland"},
    {"Code": "BLD-SOUTH", "Description": "South Campus Building", "Address": "789 Random Ave", "City": "Portland"},
    {"Code": "BLD-EAST",  "Description": "East Campus Building",  "Address": "220 SE Division St",  "City": "Springfield"}
]

bld_ids = {}
for b in buildings_data:
    cid = create_card(building_cls, b, token)
    bld_ids[b["Code"]] = cid
    print(f"Created Building {b['Code']}: {cid}")

# 4. Create Floors (with Intentional Linkage Errors)
# FLR-N-01: Correct (North)
# FLR-N-02: WRONG (Linked to South) -> Needs move to North
# FLR-S-01: Correct (South)
# FLR-S-02: Correct (South)
# FLR-E-01: WRONG (Linked to North) -> Needs move to East
# FLR-E-02: Correct (East)

floors_data = [
    {"Code": "FLR-N-01", "Description": "North 1st Floor", "target": "BLD-NORTH"},
    {"Code": "FLR-N-02", "Description": "North 2nd Floor", "target": "BLD-SOUTH"}, # ERROR
    {"Code": "FLR-S-01", "Description": "South 1st Floor", "target": "BLD-SOUTH"},
    {"Code": "FLR-S-02", "Description": "South 2nd Floor", "target": "BLD-SOUTH"},
    {"Code": "FLR-E-01", "Description": "East 1st Floor",  "target": "BLD-NORTH"}, # ERROR
    {"Code": "FLR-E-02", "Description": "East 2nd Floor",  "target": "BLD-EAST"}
]

flr_ids = {}
for f in floors_data:
    payload = {
        "Code": f["Code"],
        "Description": f["Description"],
        floor_ref_building: bld_ids[f["target"]]
    }
    cid = create_card(floor_cls, payload, token)
    flr_ids[f["Code"]] = cid
    print(f"Created Floor {f['Code']}: {cid}")

# 5. Create Rooms (with Linkage, Duplicate, and Desc Errors)
# RM-N-301: Valid room (North 2nd)
# ROOM-DUP-001: DUPLICATE of RM-N-301 (Same desc, same floor) -> Agent must delete
# ROOM-CONTAM-001: "Conference Room South-3" (Looks sim, but on South 2nd) -> Agent must KEEP
# RM-S-101: WRONG FLOOR (Linked to FLR-N-02, should be FLR-S-01)
# RM-E-201: WRONG FLOOR (Linked to FLR-E-01, should be FLR-E-02)
# RM-N-102: WRONG DESC "Storage Closet 4B" -> "Network Equipment Room 102"
# RM-S-203: WRONG DESC "Executive Office Suite" -> "Mechanical Plant Room 203"
# RM-E-101: Control (Correct)

rooms_data = [
    {"Code": "RM-N-301",        "Desc": "Conference Room North-3", "target": "FLR-N-02"},
    {"Code": "ROOM-DUP-001",    "Desc": "Conference Room North-3", "target": "FLR-N-02"}, # Duplicate
    {"Code": "ROOM-CONTAM-001", "Desc": "Conference Room South-3", "target": "FLR-S-02"}, # Contam
    {"Code": "RM-S-101",        "Desc": "Office Suite South-1",    "target": "FLR-N-02"}, # Wrong Floor (N-02 instead of S-01)
    {"Code": "RM-E-201",        "Desc": "Lab East-2",             "target": "FLR-E-01"}, # Wrong Floor (E-01 instead of E-02)
    {"Code": "RM-N-102",        "Desc": "Storage Closet 4B",       "target": "FLR-N-01"}, # Wrong Desc
    {"Code": "RM-S-203",        "Desc": "Executive Office Suite",  "target": "FLR-S-02"}, # Wrong Desc
    {"Code": "RM-E-101",        "Desc": "Lobby East-1",           "target": "FLR-E-01"}  # Control
]

rm_ids = {}
for r in rooms_data:
    payload = {
        "Code": r["Code"],
        "Description": r["Desc"],
        room_ref_floor: flr_ids[r["target"]]
    }
    cid = create_card(room_cls, payload, token)
    rm_ids[r["Code"]] = cid
    print(f"Created Room {r['Code']}: {cid}")


# 6. Save Baseline for Verifier
# We save the IDs so we can look them up later to check their new state
baseline = {
    "classes": {
        "building": building_cls,
        "floor": floor_cls,
        "room": room_cls
    },
    "ref_fields": {
        "floor_to_building": floor_ref_building,
        "room_to_floor": room_ref_floor
    },
    "ids": {
        "buildings": bld_ids,
        "floors": flr_ids,
        "rooms": rm_ids
    },
    "expected_corrections": {
        "BLD-NORTH": {"Address": "456 NW Flanders St"},
        "BLD-SOUTH": {"Address": "101 SW Columbia St"},
        "BLD-EAST":  {"City": "Portland"},
        "FLR-N-02":  {"target_building": bld_ids["BLD-NORTH"]},
        "FLR-E-01":  {"target_building": bld_ids["BLD-EAST"]},
        "RM-S-101":  {"target_floor": flr_ids["FLR-S-01"]},
        "RM-E-201":  {"target_floor": flr_ids["FLR-E-02"]},
        "RM-N-102":  {"Description": "Network Equipment Room 102"},
        "RM-S-203":  {"Description": "Mechanical Plant Room 203"}
    }
}

with open("/tmp/shr_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2)

print("Baseline saved to /tmp/shr_baseline.json")
PYEOF

# Create the Audit Report on the Desktop
cat > /home/ga/Desktop/spatial_audit_corrections.csv << 'CSVEOF'
RecordType,Code,IssueType,CurrentValue,CorrectValue,Notes
Building,BLD-NORTH,wrong_address,"123 Old Industrial Rd","456 NW Flanders St","Physical address verified during site visit"
Building,BLD-SOUTH,wrong_address,"789 Random Ave","101 SW Columbia St","Physical address verified during site visit"
Building,BLD-EAST,wrong_city,"Springfield","Portland","City was from previous owner HQ location"
Floor,FLR-N-02,wrong_building,BLD-SOUTH,BLD-NORTH,"2nd floor North building was linked to South during import"
Floor,FLR-E-01,wrong_building,BLD-NORTH,BLD-EAST,"1st floor East building was linked to North during import"
Room,RM-S-101,wrong_floor,FLR-N-02,FLR-S-01,"South bldg room mistakenly linked to North floor"
Room,RM-E-201,wrong_floor,FLR-E-01,FLR-E-02,"East bldg room on wrong floor"
Room,ROOM-DUP-001,duplicate,,"Deactivate","Exact duplicate of RM-N-301 in BLD-NORTH - created by double import"
Room,ROOM-CONTAM-001,NOT_A_DUPLICATE,,"DO NOT DELETE","Similar name to RM-N-301 but is in BLD-SOUTH - legitimate room - PRESERVE"
Room,RM-N-102,wrong_description,"Storage Closet 4B","Network Equipment Room 102","Room was repurposed before acquisition"
Room,RM-S-203,wrong_description,"Executive Office Suite","Mechanical Plant Room 203","Room was converted during renovation"
CSVEOF

chown ga:ga /home/ga/Desktop/spatial_audit_corrections.csv
chmod 644 /home/ga/Desktop/spatial_audit_corrections.csv

# Start Firefox on Login Page
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for Firefox
if ! wait_for_window "firefox|mozilla|openmaint" 30; then
    echo "WARNING: Firefox window not detected"
fi
focus_firefox || true

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial Screenshot
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="