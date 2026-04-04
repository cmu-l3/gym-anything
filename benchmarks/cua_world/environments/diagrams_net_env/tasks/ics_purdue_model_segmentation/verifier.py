#!/usr/bin/env python3
import json
import os
import sys

def verify_ics_purdue_model_segmentation(traj, env_info, task_info):
    """
    Verifies that the factory network has been segmented according to the Purdue Model.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy functionality unavailable"}

    # 1. Retrieve Result JSON
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    analysis = result.get("diagram_analysis", {})
    if "error" in analysis:
        return {"passed": False, "score": 0, "feedback": f"Diagram parsing error: {analysis['error']}"}

    containers = analysis.get("containers_found", [])
    placements = analysis.get("device_placements", [])
    firewall_count = analysis.get("firewall_count", 0)
    pdf_exists = result.get("pdf_exists", False)
    
    score = 0
    feedback = []

    # 3. Scoring Criteria

    # A. Containers Created (20 pts)
    # Expect 5 levels: L4, DMZ, L3, L2, L1
    required_levels = {
        "level 4": ["level 4", "enterprise", "corp"],
        "dmz": ["dmz", "demilitarized"],
        "level 3": ["level 3", "operations", "mom"],
        "level 2": ["level 2", "supervisory"],
        "level 1": ["level 1", "basic", "control"]
    }
    
    found_levels = 0
    for level_key, keywords in required_levels.items():
        if any(any(k in c_name for k in keywords) for c_name in containers):
            found_levels += 1
    
    score += (found_levels * 4) # Max 20
    feedback.append(f"Found {found_levels}/5 Purdue levels.")

    # B. Device Placement (50 pts)
    # Map devices to their correct zone keywords
    inventory_map = {
        "erp": ["level 4", "enterprise"],
        "email": ["level 4", "enterprise"],
        "jump": ["dmz"],
        "historian": ["level 3", "operations"],
        "mes": ["level 3", "operations"],
        "hmi": ["level 2", "supervisory"],
        "scada": ["level 2", "supervisory"],
        "plc": ["level 1", "basic", "control"],
        "robot": ["level 1", "basic", "control"],
        "vfd": ["level 1", "basic", "control"],
        "pump": ["level 1", "basic", "control"]
    }
    
    correct_placements = 0
    total_checks = 0
    
    for item in placements:
        device_label = item.get("device", "")
        container_label = item.get("container", "")
        
        # Identify which device this is
        target_device = None
        for key in inventory_map:
            if key in device_label:
                target_device = key
                break
        
        if target_device:
            total_checks += 1
            # Check if container label matches allowed zones
            allowed_zones = inventory_map[target_device]
            if any(z in container_label for z in allowed_zones):
                correct_placements += 1
    
    # Cap total checks to expected number (approx 10-11 devices)
    # Score is proportional
    if total_checks > 0:
        placement_score = (correct_placements / 10) * 50 # Normalize to 50 pts
        score += min(50, placement_score)
        feedback.append(f"Correctly placed {correct_placements} devices into zones.")
    else:
        feedback.append("No devices found inside containers.")

    # C. Firewalls (15 pts)
    if firewall_count >= 2:
        score += 15
        feedback.append("Firewalls detected.")
    elif firewall_count == 1:
        score += 7
        feedback.append("Only one firewall detected.")
    else:
        feedback.append("No firewalls detected.")

    # D. PDF Export (15 pts)
    if pdf_exists:
        score += 15
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": " ".join(feedback)
    }