#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Network Provisioning Engine Result ==="

# Force save all open files in VSCode
focus_vscode_window 2>/dev/null || true
sleep 0.5
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Execute hidden tests against the agent's code inside the container.
# This approach safely evaluates logic correctness without exposing the test suite to tampering.
python3 << 'PYEOF'
import sys
import json
import ipaddress
import traceback

# Insert workspace at top of path so we import the agent's modified models
sys.path.insert(0, '/home/ga/workspace/net_provisioner')

results = {
    "ipam_fixed": False,
    "acl_fixed": False,
    "bgp_fixed": False,
    "vlan_fixed": False,
    "json_fixed": False,
    "errors": []
}

# 1. Test IPAM
try:
    from models.ipam import check_overlap
    # Should correctly identify a /23 overlapping with a /24
    if check_overlap('10.0.0.0/23', '10.0.0.0/24') and not check_overlap('10.0.1.0/24', '10.0.2.0/24'):
        results["ipam_fixed"] = True
except Exception as e:
    results["errors"].append(f"IPAM Error: {str(e)}")

# 2. Test ACL Wildcard
try:
    from models.acl_builder import get_wildcard_mask
    # /28 netmask is 255.255.255.240 -> wildcard is 0.0.0.15
    if get_wildcard_mask('192.168.1.0/28') == '0.0.0.15' and get_wildcard_mask('10.0.0.0/24') == '0.0.0.255':
        results["acl_fixed"] = True
except Exception as e:
    results["errors"].append(f"ACL Error: {str(e)}")

# 3. Test BGP
try:
    from models.bgp import build_peer_config
    ibgp = build_peer_config('10.0.0.1', 65000, 65000)
    ebgp = build_peer_config('10.0.0.2', 65001, 65000)
    if ('update-source Loopback0' in ibgp) and ('update-source Loopback0' not in ebgp):
        results["bgp_fixed"] = True
except Exception as e:
    results["errors"].append(f"BGP Error: {str(e)}")

# 4. Test VLANs
try:
    from models.vlans import allocate_vlan_range
    if allocate_vlan_range(100, 105) == [100, 101, 102, 103, 104, 105]:
        results["vlan_fixed"] = True
except Exception as e:
    results["errors"].append(f"VLAN Error: {str(e)}")

# 5. Test JSON
try:
    from utils.serializer import NetworkJSONEncoder
    data = {'gw': ipaddress.IPv4Interface('192.168.1.1/24')}
    out = json.dumps(data, cls=NetworkJSONEncoder)
    if '192.168.1.1/24' in out:
        results["json_fixed"] = True
except Exception as e:
    results["errors"].append(f"JSON Error: {str(e)}")

# Export results
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json