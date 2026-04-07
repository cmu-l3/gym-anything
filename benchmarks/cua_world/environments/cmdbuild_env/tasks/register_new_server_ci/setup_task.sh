#!/bin/bash
echo "=== Setting up register_new_server_ci task ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_cmdbuild 240; then
  echo "ERROR: CMDBuild is not reachable"
  exit 1
fi

date +%s > /tmp/task_start_time.txt

# Create the server specification document on the Desktop
# This uses realistic Dell PowerEdge R760 specs from Dell's actual product line
cat > /home/ga/Desktop/server_spec_r760.txt << 'SPEC'
========================================
  SERVER PROCUREMENT SPECIFICATION
  Purchase Order: PO-2026-04172
  Date: 2026-04-04
========================================

ASSET REGISTRATION DETAILS
--------------------------
Code:         SRV-R760-0417
Description:  Dell PowerEdge R760 - Production DB Cluster Node 3
Serial No:    CN-0JVFK7-28190-5D3-09RM

HARDWARE CONFIGURATION
--------------------------
Model:        Dell PowerEdge R760
Form Factor:  2U Rack Mount
Processors:   2x Intel Xeon Gold 6430 (2.1GHz, 32-core)
Memory:       512GB DDR5-4800 ECC RDIMM (16x 32GB)
Storage:      8x 2.4TB SAS 10K RPM (RAID 10 via PERC H965i)
Network:      4x 25GbE SFP28 (Broadcom 57504)
Management:   iDRAC9 Enterprise, IP: 10.20.30.47
Power:        2x 1400W Platinum PSU (redundant)
OS:           Red Hat Enterprise Linux 9.3

DEPLOYMENT DETAILS
--------------------------
Location:     Data Center East, Row 5, Rack 12
Rack Unit:    U12-14
Power:        PDU-A Port 8, PDU-B Port 8
Network Port: TOR-SW-R5-01 Ports 25-28

NOTES FOR CMDB ENTRY
--------------------------
Enter the following in the Notes field:
Rack U12-14, PDU-A Port 8, iDRAC IP 10.20.30.47, 2x Intel Xeon Gold 6430 / 512GB DDR5 / 8x 2.4TB SAS

========================================
SPEC
chown ga:ga /home/ga/Desktop/server_spec_r760.txt
chmod 644 /home/ga/Desktop/server_spec_r760.txt

# Record baseline: count existing server CIs before the task
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
    # Broader fallback: any CI class
    for name in ["CI", "Computer", "Hardware", "Asset", "NetworkDevice"]:
        found = find_class(f"^{name}$", token)
        if found:
            server_cls = found
            break

if not server_cls:
    print("WARNING: No suitable server class found, will discover during testing", file=sys.stderr)
    server_cls = "UNKNOWN"

initial_count = 0
if server_cls != "UNKNOWN":
    initial_count = count_cards(server_cls, token)

baseline = {
    "server_class": server_cls,
    "initial_count": initial_count,
    "expected_code": "SRV-R760-0417",
    "expected_serial": "CN-0JVFK7-28190-5D3-09RM",
    "expected_description": "Dell PowerEdge R760 - Production DB Cluster Node 3"
}

with open("/tmp/register_server_baseline.json", "w") as f:
    json.dump(baseline, f)

print(f"Baseline: class={server_cls}, initial_count={initial_count}")
PYEOF

# Start browser at CMDBuild login page
restart_firefox "$CMDBUILD_URL"

if ! wait_for_rendered_browser_view /tmp/task_start_screenshot.png 60; then
  echo "WARNING: Browser view did not stabilize before timeout"
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Server spec file: /home/ga/Desktop/server_spec_r760.txt"
