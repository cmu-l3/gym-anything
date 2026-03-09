#!/usr/bin/env python3
"""
Verifier for small_business_network_topology task.

Scoring Criteria:
1. Anti-gaming: File created/modified during task (10 pts)
2. Devices: >12 devices found matching inventory (20 pts)
3. Connections: >10 connections found (15 pts)
4. Attributes: IP addresses and network terms found (25 pts)
5. Structure: >2 pages and >3 zone boundaries (20 pts)
6. Export: PNG file exists and has size (10 pts)

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_network_topology(traj, env_info, task_info):
    """
    Verify the created network topology diagram.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Analysis data from export script
    analysis = result.get("topology_analysis", {})
    
    # 1. Anti-gaming (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback_parts.append("File saved successfully.")
    else:
        feedback_parts.append("File not saved or not modified.")
        return {"passed": False, "score": 0, "feedback": "No file saved."}

    # 2. Devices (20 pts)
    device_matches = analysis.get("device_matches", 0)
    if device_matches >= 12:
        score += 20
        feedback_parts.append(f"Excellent device coverage ({device_matches}/14+).")
    elif device_matches >= 8:
        score += 10
        feedback_parts.append(f"Good device coverage ({device_matches}/14+).")
    elif device_matches >= 4:
        score += 5
        feedback_parts.append(f"Partial device coverage ({device_matches}/14+).")
    else:
        feedback_parts.append(f"Few devices found matching inventory ({device_matches}).")

    # 3. Connections (15 pts)
    edges = analysis.get("num_edges", 0)
    if edges >= 12:
        score += 15
        feedback_parts.append(f"Topology connectivity looks good ({edges} edges).")
    elif edges >= 8:
        score += 10
        feedback_parts.append(f"Topology connectivity acceptable ({edges} edges).")
    elif edges >= 3:
        score += 5
        feedback_parts.append(f"Sparse connectivity ({edges} edges).")
    else:
        feedback_parts.append("Almost no connections found.")

    # 4. Content & Attributes (25 pts)
    ip_count = analysis.get("ip_pattern_count", 0)
    has_terms = analysis.get("has_network_terms", False)
    
    attr_score = 0
    if ip_count >= 6: attr_score += 15
    elif ip_count >= 3: attr_score += 5
    
    if has_terms: attr_score += 10
    
    score += attr_score
    feedback_parts.append(f"Content attributes score: {attr_score}/25 (IPs: {ip_count}).")

    # 5. Structure & Zones (20 pts)
    pages = analysis.get("num_pages", 0)
    zones = analysis.get("zone_boundaries", 0)
    
    struct_score = 0
    if pages >= 2: struct_score += 10
    else: feedback_parts.append("Missing IP Plan page.")
    
    if zones >= 3: struct_score += 10
    elif zones >= 1: struct_score += 5
    else: feedback_parts.append("Missing zone boundaries.")
    
    score += struct_score
    feedback_parts.append(f"Structure score: {struct_score}/20.")

    # 6. PNG Export (10 pts)
    if result.get("png_exists") and result.get("png_size", 0) > 2000:
        score += 10
        feedback_parts.append("PNG export successful.")
    else:
        feedback_parts.append("PNG export missing or empty.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }