#!/bin/bash
echo "=== Setting up update_ci_serial_numbers task ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_cmdbuild 240; then
  echo "ERROR: CMDBuild is not reachable"
  exit 1
fi

date +%s > /tmp/task_start_time.txt

# Create the audit reconciliation CSV on the Desktop
# These serial numbers are realistic HP/Dell/Cisco format serials
cat > /home/ga/Desktop/serial_audit_q1_2026.csv << 'CSV'
Code,AssetDescription,OldSerial_CMDB,VerifiedSerial_Physical,AuditNotes
SRV-AUDIT-001,HP ProLiant DL380 Gen10 - Web Frontend,PLACEHOLDER-001,MXL5289JQT,Verified at DC-West Rack 3 U18
SRV-AUDIT-002,Cisco UCS C220 M6 - App Server,PLACEHOLDER-002,FCH2517V0RK,Verified at DC-West Rack 5 U22
SRV-AUDIT-003,Dell PowerEdge R640 - Backup Node,PLACEHOLDER-003,HVKNT43,Verified at DC-East Rack 1 U10
CSV
chown ga:ga /home/ga/Desktop/serial_audit_q1_2026.csv
chmod 644 /home/ga/Desktop/serial_audit_q1_2026.csv

# Seed the 3 server CIs with placeholder serial numbers using the API
python3 << 'PYEOF'
import sys, json
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

# Find the Server CI class
server_cls = None
for name in ["Server", "VirtualServer", "PhysicalServer", "InternalServer"]:
    found = find_class(f"^{name}$", token)
    if found:
        server_cls = found
        break

if not server_cls:
    classes = find_all_classes(r"[Ss]erver", token)
    if classes:
        server_cls = classes[0]

if not server_cls:
    for name in ["CI", "Computer", "Hardware", "Asset", "NetworkDevice"]:
        found = find_class(f"^{name}$", token)
        if found:
            server_cls = found
            break

if not server_cls:
    print("WARNING: No suitable server class found", file=sys.stderr)
    server_cls = "UNKNOWN"

print(f"Using Server class: {server_cls}")

# Get available attributes to understand the schema
if server_cls != "UNKNOWN":
    attrs = get_class_attributes(server_cls, token)
    serial_field = "SerialNumber"
    for attr in attrs:
        attr_name = attr.get("_id", "") or attr.get("name", "")
        if "serial" in attr_name.lower():
            serial_field = attr_name
            break
    print(f"Serial field: {serial_field}")
else:
    serial_field = "SerialNumber"

assets_to_seed = [
    {"Code": "SRV-AUDIT-001", "Description": "HP ProLiant DL380 Gen10 - Web Frontend", serial_field: "PLACEHOLDER-001", "Notes": ""},
    {"Code": "SRV-AUDIT-002", "Description": "Cisco UCS C220 M6 - App Server", serial_field: "PLACEHOLDER-002", "Notes": ""},
    {"Code": "SRV-AUDIT-003", "Description": "Dell PowerEdge R640 - Backup Node", serial_field: "PLACEHOLDER-003", "Notes": ""},
]

created_ids = {}

if server_cls != "UNKNOWN":
    for asset in assets_to_seed:
        code = asset["Code"]
        # Check if already exists
        existing = get_cards(server_cls, token, limit=200)
        found = None
        for c in existing:
            if c.get("Code", "") == code:
                found = c
                break

        if found:
            card_id = found["_id"]
            # Reset to placeholder state
            update_card(server_cls, card_id, {serial_field: asset[serial_field], "Notes": "", "Description": asset["Description"]}, token)
            created_ids[code] = card_id
            print(f"  Reset existing {code} (id={card_id})")
        else:
            card_id = create_card(server_cls, asset, token)
            if card_id:
                created_ids[code] = card_id
                print(f"  Created {code} (id={card_id})")
            else:
                print(f"  FAILED to create {code}", file=sys.stderr)

baseline = {
    "server_class": server_cls,
    "serial_field": serial_field,
    "asset_ids": created_ids,
    "expected_updates": {
        "SRV-AUDIT-001": "MXL5289JQT",
        "SRV-AUDIT-002": "FCH2517V0RK",
        "SRV-AUDIT-003": "HVKNT43"
    }
}

with open("/tmp/serial_audit_baseline.json", "w") as f:
    json.dump(baseline, f)

print(f"Baseline saved: {len(created_ids)} assets seeded")
PYEOF

# Start browser at CMDBuild login page
restart_firefox "$CMDBUILD_URL"

if ! wait_for_rendered_browser_view /tmp/task_start_screenshot.png 60; then
  echo "WARNING: Browser view did not stabilize before timeout"
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Audit CSV: /home/ga/Desktop/serial_audit_q1_2026.csv"
