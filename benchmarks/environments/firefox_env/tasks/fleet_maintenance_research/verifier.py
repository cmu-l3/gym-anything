#!/usr/bin/env python3
"""
Verifier for fleet_maintenance_research task.
Checks the JSON output for correct vehicle specs and part numbers,
and verifies browser artifacts (bookmarks/history).
"""

import json
import logging
import tempfile
import os
import re

logger = logging.getLogger(__name__)

def normalize_part(part_num):
    """Normalize part number: remove whitespace, make uppercase."""
    if not isinstance(part_num, str):
        return ""
    return part_num.strip().upper()

def check_viscosity(user_val, accepted_list):
    """Check if user viscosity matches accepted variants."""
    if not user_val or not isinstance(user_val, str):
        return False
    # Normalize: remove spaces, lowercase
    norm_user = user_val.replace(" ", "").replace("-", "").lower()
    for acc in accepted_list:
        norm_acc = acc.replace(" ", "").replace("-", "").lower()
        if norm_user == norm_acc:
            return True
    return False

def check_capacity(user_val, target, tolerance):
    """Check if oil capacity is within tolerance."""
    try:
        val = float(user_val)
        return abs(val - target) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_fleet_maintenance_research(traj, env_info, task_info):
    """
    Verification logic for Fleet Maintenance Research.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy_from_env missing"}

    # Load metadata (ground truth)
    metadata = task_info.get('metadata', {})
    vehicles_truth = metadata.get('vehicles', {})

    # Retrieve result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize Score
    score = 0
    feedback = []
    
    # 1. Check File Existence & Freshness (10 pts)
    if result_data.get('file_exists') and result_data.get('file_fresh'):
        score += 10
        feedback.append("JSON file created successfully.")
    else:
        feedback.append("JSON file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Check Browser Artifacts (30 pts)
    # History (15 pts)
    if result_data.get('rockauto_visits', 0) > 0:
        score += 15
        feedback.append("RockAuto history found.")
    else:
        feedback.append("No RockAuto history found.")

    # Bookmarks (15 pts)
    if result_data.get('fleet_folder_exists'):
        cnt = result_data.get('fleet_folder_count', 0)
        if cnt >= 3:
            score += 15
            feedback.append(f"Bookmark folder 'Fleet Parts' found with {cnt} items.")
        elif cnt > 0:
            score += 10
            feedback.append(f"Bookmark folder 'Fleet Parts' found but only has {cnt} items (expected 3).")
        else:
            score += 5
            feedback.append("Bookmark folder 'Fleet Parts' is empty.")
    else:
        feedback.append("Bookmark folder 'Fleet Parts' NOT found.")

    # 3. Check JSON Content (60 pts max)
    user_json = result_data.get('user_json_content', {})
    
    # We expect keys: ford_f150, toyota_rav4, honda_civic
    for v_key, v_truth in vehicles_truth.items():
        if v_key not in user_json:
            feedback.append(f"Missing vehicle entry: {v_key}.")
            continue
            
        u_veh = user_json[v_key]
        v_name = v_key.replace("_", " ").title()
        
        # Check Viscosity (5 pts)
        if check_viscosity(u_veh.get('oil_viscosity'), v_truth['oil_viscosity']):
            score += 5
        else:
            feedback.append(f"Incorrect viscosity for {v_name}.")

        # Check Capacity (5 pts)
        if check_capacity(u_veh.get('oil_capacity_quarts'), v_truth['oil_capacity_qt'], v_truth['oil_capacity_tolerance']):
            score += 5
        else:
            feedback.append(f"Incorrect oil capacity for {v_name} (Expected ~{v_truth['oil_capacity_qt']} qt).")

        # Check Oil Filter (5 pts)
        # Truth list contains accepted WIX numbers
        u_oil_filter = normalize_part(u_veh.get('oil_filter_wix_part'))
        if u_oil_filter in [normalize_part(x) for x in v_truth['wix_oil_filters']]:
            score += 5
        else:
            feedback.append(f"Incorrect WIX oil filter for {v_name} (Got: {u_oil_filter}).")

        # Check Cabin Filter (5 pts)
        u_cabin_filter = normalize_part(u_veh.get('cabin_filter_wix_part'))
        if u_cabin_filter in [normalize_part(x) for x in v_truth['wix_cabin_filters']]:
            score += 5
        else:
            feedback.append(f"Incorrect WIX cabin filter for {v_name} (Got: {u_cabin_filter}).")

    # Final Score Calculation
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }