#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Network Provisioning Engine Task ==="

WORKSPACE="/home/ga/workspace/net_provisioner"
sudo -u ga mkdir -p "$WORKSPACE/models"
sudo -u ga mkdir -p "$WORKSPACE/utils"
sudo -u ga mkdir -p "$WORKSPACE/tests"

# ─────────────────────────────────────────────────────────
# 1. Generate buggy models/ipam.py (Subnet Overlap Bug)
# ─────────────────────────────────────────────────────────
cat > "$WORKSPACE/models/ipam.py" << 'PYEOF'
import ipaddress

def check_overlap(cidr1: str, cidr2: str) -> bool:
    """
    Check if two IPv4 subnets overlap.
    Returns True if they overlap, False otherwise.
    """
    # BUG: Just does string equality, fails to detect actual CIDR overlaps
    # (e.g., 10.0.0.0/23 overlaps with 10.0.0.0/24)
    if cidr1 == cidr2:
        return True
    return False
PYEOF

# ─────────────────────────────────────────────────────────
# 2. Generate buggy models/acl_builder.py (Wildcard Mask Bug)
# ─────────────────────────────────────────────────────────
cat > "$WORKSPACE/models/acl_builder.py" << 'PYEOF'
import ipaddress

def get_wildcard_mask(cidr: str) -> str:
    """
    Calculate Cisco wildcard mask for a given subnet.
    Example: 192.168.1.0/24 -> 0.0.0.255
    """
    net = ipaddress.IPv4Network(cidr, strict=False)
    # BUG: Subtracts the network address octets instead of the netmask octets
    return '.'.join(str(255 - int(octet)) for octet in str(net.network_address).split('.'))
PYEOF

# ─────────────────────────────────────────────────────────
# 3. Generate buggy models/bgp.py (BGP Peering Bug)
# ─────────────────────────────────────────────────────────
cat > "$WORKSPACE/models/bgp.py" << 'PYEOF'
def build_peer_config(peer_ip: str, remote_as: int, local_as: int) -> str:
    """
    Build BGP neighbor configuration.
    Internal BGP (iBGP) peers must use Loopback0 as the update-source.
    External BGP (eBGP) peers should not.
    """
    config = [f"neighbor {peer_ip} remote-as {remote_as}"]
    
    # BUG: Uses != (eBGP) instead of == (iBGP) for applying the loopback source
    if remote_as != local_as:
        config.append(f"neighbor {peer_ip} update-source Loopback0")
        
    return '\n'.join(config)
PYEOF

# ─────────────────────────────────────────────────────────
# 4. Generate buggy models/vlans.py (Off-by-one Boundary Bug)
# ─────────────────────────────────────────────────────────
cat > "$WORKSPACE/models/vlans.py" << 'PYEOF'
from typing import List

def allocate_vlan_range(start_id: int, end_id: int) -> List[int]:
    """
    Generate a list of VLAN IDs from start_id to end_id (inclusive).
    """
    # BUG: Python's range() is exclusive at the end, dropping the last VLAN
    return list(range(start_id, end_id))
PYEOF

# ─────────────────────────────────────────────────────────
# 5. Generate buggy utils/serializer.py (JSON encoding crash)
# ─────────────────────────────────────────────────────────
cat > "$WORKSPACE/utils/serializer.py" << 'PYEOF'
import json
import ipaddress

class NetworkJSONEncoder(json.JSONEncoder):
    """
    Custom JSON encoder that handles Python ipaddress objects.
    """
    def default(self, obj):
        if isinstance(obj, ipaddress.IPv4Network):
            return str(obj)
        if isinstance(obj, ipaddress.IPv4Address):
            return str(obj)
        # BUG: Missing handling for IPv4Interface, which causes a TypeError
        # when exporting gateway configurations.
        return super().default(obj)
PYEOF

# ─────────────────────────────────────────────────────────
# 6. Generate the visible Test Suite
# ─────────────────────────────────────────────────────────
cat > "$WORKSPACE/tests/test_provisioner.py" << 'PYEOF'
import pytest
import ipaddress
import json
from models.ipam import check_overlap
from models.acl_builder import get_wildcard_mask
from models.bgp import build_peer_config
from models.vlans import allocate_vlan_range
from utils.serializer import NetworkJSONEncoder

def test_ipam_overlap():
    assert check_overlap('10.0.0.0/24', '10.0.0.0/24') == True
    assert check_overlap('10.0.0.0/23', '10.0.0.0/24') == True, "Should detect nested overlap"
    assert check_overlap('10.0.1.0/24', '10.0.2.0/24') == False

def test_acl_wildcard():
    assert get_wildcard_mask('192.168.1.0/24') == '0.0.0.255'
    assert get_wildcard_mask('10.0.0.0/28') == '0.0.0.15', "Incorrect wildcard for /28 subnet"

def test_bgp_peering():
    ibgp_config = build_peer_config('10.0.0.1', 65000, 65000)
    ebgp_config = build_peer_config('192.0.2.1', 65001, 65000)
    assert 'update-source Loopback0' in ibgp_config, "iBGP peers require Loopback0 source"
    assert 'update-source Loopback0' not in ebgp_config, "eBGP peers should not use Loopback0"

def test_vlan_allocation():
    vlans = allocate_vlan_range(100, 105)
    assert vlans == [100, 101, 102, 103, 104, 105], "Failed to include upper boundary in VLAN range"

def test_json_serializer():
    data = {
        "network": ipaddress.IPv4Network("10.0.0.0/24"),
        "gateway": ipaddress.IPv4Interface("10.0.0.1/24")
    }
    encoded = json.dumps(data, cls=NetworkJSONEncoder)
    assert "10.0.0.1/24" in encoded, "Failed to serialize IPv4Interface"
PYEOF

# Adjust permissions
chown -R ga:ga "$WORKSPACE"

# Start VS Code
kill_vscode
su - ga -c "DISPLAY=:1 code $WORKSPACE &"
sleep 5

# Focus and maximize VS Code
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Record initial timestamps and states
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="