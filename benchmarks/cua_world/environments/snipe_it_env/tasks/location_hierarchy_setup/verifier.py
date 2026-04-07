#!/usr/bin/env python3
"""Verifier for location_hierarchy_setup task.

Scoring breakdown (100 points):
  C1: Parent location exists with correct fields (15 pts)
  C2: Three child locations exist with correct parent (15 pts)
  C3: Child names match expected values (10 pts)
  C4: ASSET-WC01 relocated correctly (10 pts)
  C5: ASSET-WC02 relocated correctly (10 pts)
  C6: ASSET-WC03 relocated correctly (10 pts)
  C7: ASSET-WC04 relocated correctly (10 pts)
  C8: Manager correctly assigned (10 pts)
  C9: Staging Warehouse is empty (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/location_hierarchy_result.json"


def verify_location_hierarchy_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    parent = result.get("parent", {})
    children = result.get("children", {})
    assets = result.get("assets", {})
    staging = result.get("staging_warehouse", {})
    task_start = int(result.get("task_start_time", 0))

    # --- Do-nothing gate & Anti-gaming (was it created during the task?) ---
    if not parent.get("found"):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: Parent location 'West Campus Medical Center' not created."}

    created_at = int(parent.get("created_at", "0"))
    if created_at < task_start:
        feedback.append("WARNING: Location appears to have been created before task started.")

    # --- C1: Parent location exists with fields (15 pts) ---
    c1_score = 5 # 5 pts just for finding it
    if parent.get("address", "").strip() == "4500 Oak Park Boulevard":
        c1_score += 3
    if parent.get("city", "").strip() == "Portland":
        c1_score += 3
    if parent.get("state", "").strip() == "OR":
        c1_score += 2
    if parent.get("zip", "").strip() == "97201":
        c1_score += 2
    
    score += c1_score
    if c1_score == 15:
        feedback.append("C1: Parent location created with all correct address fields (+15)")
    else:
        feedback.append(f"C1: Parent location created but missing/incorrect fields (+{c1_score})")

    # --- C2: Three child locations exist (15 pts) ---
    child_count = int(children.get("count", 0))
    if child_count >= 3:
        score += 15
        feedback.append("C2: 3 child locations linked to parent correctly (+15)")
    elif child_count > 0:
        c2_score = child_count * 5
        score += c2_score
        feedback.append(f"C2: {child_count}/3 child locations linked to parent (+{c2_score})")
    else:
        feedback.append("C2: No child locations linked to parent (+0)")

    # --- C3: Child names correct (10 pts) ---
    expected_children = [
        "WC - Emergency Department",
        "WC - Radiology Wing",
        "WC - Administrative Offices"
    ]
    actual_names = [n.strip() for n in children.get("names", [])]
    matches = sum(1 for exp in expected_children if exp in actual_names)
    
    if matches == 3:
        score += 10
        feedback.append("C3: All child location names match perfectly (+10)")
    elif matches > 0:
        c3_score = matches * 3
        score += c3_score
        feedback.append(f"C3: {matches}/3 child location names match (+{c3_score})")
    else:
        feedback.append("C3: Child location names do not match expected values (+0)")

    # --- C4-C7: Assets relocated (10 pts each) ---
    def check_asset(asset_key, expected_loc_name, criteria_num):
        a_data = assets.get(asset_key, {})
        if not a_data.get("found"):
            return 0, f"{criteria_num}: {asset_key} not found (+0)"
        
        actual_loc = a_data.get("location_name", "").strip()
        if actual_loc == expected_loc_name:
            return 10, f"{criteria_num}: {asset_key} correctly reassigned to '{expected_loc_name}' (+10)"
        else:
            return 0, f"{criteria_num}: {asset_key} is at '{actual_loc}', expected '{expected_loc_name}' (+0)"

    c4_pts, c4_msg = check_asset("WC01", "WC - Emergency Department", "C4")
    score += c4_pts; feedback.append(c4_msg)
    
    c5_pts, c5_msg = check_asset("WC02", "WC - Radiology Wing", "C5")
    score += c5_pts; feedback.append(c5_msg)
    
    c6_pts, c6_msg = check_asset("WC03", "WC - Administrative Offices", "C6")
    score += c6_pts; feedback.append(c6_msg)
    
    c7_pts, c7_msg = check_asset("WC04", "WC - Emergency Department", "C7")
    score += c7_pts; feedback.append(c7_msg)

    # --- C8: Manager correctly assigned (10 pts) ---
    if parent.get("manager_username") == "schen":
        score += 10
        feedback.append("C8: Manager correctly assigned to Sarah Chen (+10)")
    else:
        feedback.append(f"C8: Manager is '{parent.get('manager_username')}', expected 'schen' (+0)")

    # --- C9: Staging Warehouse empty (10 pts) ---
    remaining = int(staging.get("remaining_assets", 4))
    if remaining == 0:
        score += 10
        feedback.append("C9: Staging Warehouse is empty (+10)")
    else:
        feedback.append(f"C9: {remaining} assets still remain in Staging Warehouse (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }