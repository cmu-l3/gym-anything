#!/usr/bin/env python3
"""
Verifier for area_path_restructure task.

Task: Create 3 Area Paths (Backend, Frontend, Infrastructure) and reassign 8 Work Items correctly.
Verification: Programmatic check of Azure DevOps state via exported JSON.
"""

import json
import logging
import os
import tempfile
import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_area_path_restructure(traj, env_info, task_info):
    """
    Verify that the agent created the correct area paths and reassigned work items.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    # Define expected mappings (Title -> Expected Leaf Area)
    # Full path expected: TailwindTraders\Backend, etc.
    mapping = task_info.get("metadata", {}).get("work_item_mapping", {})
    required_areas = task_info.get("metadata", {}).get("required_areas", [])
    
    # Retrieve result JSON from VM
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_file.close()
    
    try:
        # Try primary path
        try:
            copy_from_env("C:/Users/Docker/task_results/area_path_restructure_result.json", tmp_file.name)
        except Exception:
            # Try alternate path style (sometimes needed for Windows paths in Linux hosts)
            copy_from_env(r"C:\Users\Docker\task_results\area_path_restructure_result.json", tmp_file.name)
            
        with open(tmp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {str(e)}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Check 1: Area Paths Created (30 points) ---
    created_areas = [a.lower() for a in result.get("areas", [])]
    areas_score = 0
    missing_areas = []
    
    for req in required_areas:
        if req.lower() in created_areas:
            areas_score += 10
        else:
            missing_areas.append(req)
            
    score += areas_score
    if missing_areas:
        feedback_parts.append(f"Missing Area Paths: {', '.join(missing_areas)}")
    else:
        feedback_parts.append("All required Area Paths created")

    # --- Check 2: Work Item Assignments (64 points) ---
    # 8 items * 8 points each
    items = result.get("work_items", [])
    assignment_score = 0
    misassigned_items = []
    
    # Helper to check if item matches expectations
    correct_count = 0
    
    for item in items:
        title = item.get("title", "")
        current_path = item.get("area_path", "")
        
        # Find expected area for this title
        expected_leaf = mapping.get(title)
        
        if expected_leaf:
            expected_full_path = f"TailwindTraders\\{expected_leaf}"
            
            # Case insensitive check
            if current_path.lower() == expected_full_path.lower():
                assignment_score += 8
                correct_count += 1
            else:
                misassigned_items.append(f"'{title}' (Found: {current_path}, Expected: {expected_full_path})")

    score += assignment_score
    if misassigned_items:
        feedback_parts.append(f"{len(misassigned_items)} items misassigned")
        # Log a few examples for feedback
        feedback_parts.append(f"Example error: {misassigned_items[0]}")
    else:
        feedback_parts.append("All work items correctly assigned")

    # --- Check 3: Root Area Clean (6 points) ---
    # Check if any items are left at 'TailwindTraders' root
    root_items = [i['title'] for i in items if i.get('area_path', '').lower() == 'tailwindtraders']
    if not root_items:
        score += 6
        feedback_parts.append("Root area path is clean")
    else:
        feedback_parts.append(f"{len(root_items)} items left in root area (e.g., {root_items[0]})")

    # --- Check 4: Anti-Gaming (Timestamp check) ---
    # Verify items were modified AFTER task start
    task_start_str = result.get("task_start_time")
    
    try:
        # Simple ISO date compare (strings sort correctly if ISO format)
        modified_count = 0
        for item in items:
            changed_date = item.get("changed_date", "")
            if changed_date > task_start_str:
                modified_count += 1
        
        if modified_count < 4:
            feedback_parts.append(f"WARNING: Only {modified_count} items modified during task window")
            # Penalize if it looks like no work was done, but rely on state score primarily
    except Exception:
        pass # Date parsing fallback ignored for robustness

    # Final Verification
    passed = score >= 60 and len(missing_areas) == 0 and correct_count >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }