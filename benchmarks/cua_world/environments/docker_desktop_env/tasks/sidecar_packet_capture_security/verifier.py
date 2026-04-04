#!/usr/bin/env python3
"""
Verifier for Sidecar Packet Capture Security Task.
Checks configuration compliance (No Privileged, Caps only) and functionality (PCAP generation).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sidecar_packet_capture(traj, env_info, task_info):
    """
    Verifies the sidecar packet capture task.
    
    Criteria:
    1. Sniffer container exists and is running (20 pts)
    2. Network mode shares namespace with auth-service (25 pts)
    3. Security: Not Privileged AND has NET_ADMIN/NET_RAW caps (25 pts)
    4. Functionality: PCAP file exists and has content (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Container Running (20 pts)
    if result.get("sniffer_found") and result.get("is_running"):
        score += 20
        feedback.append("Sniffer container is running")
    elif result.get("sniffer_found"):
        feedback.append("Sniffer container found but NOT running")
    else:
        feedback.append("Sniffer container NOT found")

    # 2. Network Namespace (25 pts)
    net_mode = result.get("network_mode", "")
    auth_id = result.get("auth_container_id", "unknown")
    
    # Valid modes: "service:auth-service" or "container:<id>"
    is_network_shared = False
    if "service:auth-service" in net_mode:
        is_network_shared = True
    elif net_mode.startswith("container:") and (auth_id in net_mode or len(net_mode) > 12):
        # We assume if it points to a container ID, it's likely the right one if setup correctly
        # The export script gets the auth_id to compare
        if auth_id in net_mode:
            is_network_shared = True
    
    if is_network_shared:
        score += 25
        feedback.append("Network namespace shared correctly")
    else:
        feedback.append(f"Network mode incorrect: '{net_mode}' (expected service:auth-service)")

    # 3. Security Compliance (25 pts)
    # Must be Privileged: False AND have Capabilities
    is_privileged = result.get("is_privileged", True) # Default to true (fail) if missing
    caps = result.get("cap_add", [])
    
    # Normalize caps list
    caps = [c.upper() for c in caps] if caps else []
    has_required_caps = "NET_ADMIN" in caps or "NET_RAW" in caps or "ALL" in caps

    if not is_privileged and has_required_caps:
        score += 25
        feedback.append("Security checks passed (Privileged: False, Caps: Present)")
    else:
        if is_privileged:
            feedback.append("SECURITY FAIL: Container is running as Privileged")
        if not has_required_caps:
            feedback.append("SECURITY FAIL: Missing required capabilities (NET_ADMIN/NET_RAW)")

    # 4. Functionality / PCAP (30 pts)
    pcap_size = int(result.get("pcap_size", 0))
    min_size = task_info.get("metadata", {}).get("min_pcap_size_bytes", 100)
    
    if pcap_size > min_size:
        score += 30
        feedback.append(f"Packet capture successful ({pcap_size} bytes)")
    elif pcap_size > 0:
        score += 10
        feedback.append(f"Packet capture file exists but is small ({pcap_size} bytes)")
    else:
        feedback.append("Packet capture file missing or empty")

    # Final Verification
    # Pass threshold: 75 pts (allows minor issues but strict on core reqs)
    # AND mandatory check: Must NOT be privileged
    passed = score >= 75 and not is_privileged

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }