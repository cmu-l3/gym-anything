#!/usr/bin/env python3
"""
Verifier for pos_system_deployment_diagram task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_pos_deployment(traj, env_info, task_info):
    """
    Verify the POS System Deployment Diagram.
    
    Criteria:
    1. Files exist and modified (10 pts)
    2. Hardware Nodes present (20 pts) - Checkout Terminal, Store Controller
    3. Peripherals present (15 pts) - Scanner, Printer, Pin Pad
    4. Software Nesting (25 pts) - Artifacts inside Nodes
    5. Connectivity & Protocols (20 pts) - Edges with labels
    6. PNG Export (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 10
        feedback.append("Draw.io file saved")
    else:
        feedback.append("Draw.io file missing or not saved")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    analysis = result.get('analysis', {})
    all_text = analysis.get('all_text', '').lower()
    nesting = analysis.get('nesting_map', {})
    # Normalize nesting keys/values to lower case for comparison
    nesting_lower = {k.lower(): v.lower() for k, v in nesting.items()}
    
    # 2. Hardware Nodes (20 pts)
    # Looking for "Checkout Terminal" and "Store Controller"
    nodes_found = 0
    if "checkout" in all_text and "terminal" in all_text:
        nodes_found += 1
    if "store" in all_text and "controller" in all_text:
        nodes_found += 1
    
    if nodes_found == 2:
        score += 20
        feedback.append("Main hardware nodes found")
    elif nodes_found == 1:
        score += 10
        feedback.append("One hardware node missing")
    else:
        feedback.append("Hardware nodes missing")

    # 3. Peripherals (15 pts)
    # Scanner, Printer, Pin Pad
    periphs_found = 0
    if "scanner" in all_text: periphs_found += 1
    if "printer" in all_text: periphs_found += 1
    if "pin" in all_text or "pad" in all_text: periphs_found += 1
    
    if periphs_found >= 3:
        score += 15
        feedback.append("All peripherals found")
    else:
        score += (periphs_found * 5)
        feedback.append(f"Found {periphs_found}/3 peripherals")

    # 4. Software Nesting (25 pts)
    # Check if software is inside hardware
    # POS Client -> Checkout Terminal
    # SQL/Transaction -> Store Controller
    
    nesting_score = 0
    
    # Helper to check if child is inside parent (fuzzy match)
    def check_nesting(child_keyword, parent_keyword):
        for child, parent in nesting_lower.items():
            if child_keyword in child and parent_keyword in parent:
                return True
        return False

    if check_nesting("pos", "terminal"): nesting_score += 10
    if check_nesting("opos", "terminal"): nesting_score += 5
    if check_nesting("sql", "controller") or check_nesting("db", "controller"): nesting_score += 5
    if check_nesting("transaction", "controller"): nesting_score += 5
    
    score += nesting_score
    if nesting_score >= 20:
        feedback.append("Software correctly nested inside nodes")
    elif nesting_score > 0:
        feedback.append("Partial software nesting detected")
    else:
        feedback.append("Software not nested inside hardware nodes")

    # 5. Connectivity & Labels (20 pts)
    # Check edges for protocol names
    edges = analysis.get('edges_found', [])
    edges_text = " ".join(edges).lower()
    
    protocols_found = 0
    required_protos = ["usb", "rs-232", "ethernet", "lan", "tcp"]
    # Relaxed: 'network' can sub for ethernet, 'com' for rs-232
    if "usb" in edges_text: protocols_found += 1
    if "rs-232" in edges_text or "com" in edges_text: protocols_found += 1
    if "ethernet" in edges_text or "network" in edges_text: protocols_found += 1
    if "lan" in edges_text or "tcp" in edges_text: protocols_found += 1
    
    if protocols_found >= 4:
        score += 20
        feedback.append("All connection protocols labeled")
    else:
        score += (protocols_found * 5)
        feedback.append(f"Connection labels: {protocols_found}/4 found")

    # 6. PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 1000:
        score += 10
        feedback.append("PNG export successful")
    else:
        feedback.append("PNG export missing or empty")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }