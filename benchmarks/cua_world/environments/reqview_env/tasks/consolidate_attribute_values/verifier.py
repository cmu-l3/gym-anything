#!/usr/bin/env python3
"""
Verifier for consolidate_attribute_values task.
Checks if the "Team" attribute in the SRS document has been standardized.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_attribute_values(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    srs_path = metadata.get('srs_path', '/home/ga/Documents/ReqView/messy_project/documents/SRS.json')
    attr_id = metadata.get('attribute_id', 'team_attr')

    # Files to fetch
    remote_files = {
        "srs": srs_path,
        "initial_counts": "/tmp/initial_counts.json",
        "task_result": "/tmp/task_result.json"
    }
    
    local_files = {}
    
    # Fetch files
    for name, path in remote_files.items():
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(path, tmp.name)
            with open(tmp.name, 'r') as f:
                local_files[name] = json.load(f)
        except Exception as e:
            logger.warning(f"Could not read {name} from {path}: {e}")
            local_files[name] = None
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    srs_data = local_files.get("srs")
    initial_counts = local_files.get("initial_counts", {})
    task_result = local_files.get("task_result", {})

    if not srs_data:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not read SRS document to verify changes."
        }

    # Analyze File Modification
    if not task_result.get("file_modified", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Project file was not modified/saved during the task. (Did you forget to Save?)"
        }

    # Helper to traverse requirements
    def get_leaves(items):
        leaves = []
        for item in items:
            if 'children' in item and item['children']:
                leaves.extend(get_leaves(item['children']))
            else:
                leaves.append(item)
        return leaves

    leaves = get_leaves(srs_data.get("data", []))
    
    # Count current values
    current_counts = {}
    
    for item in leaves:
        val = item.get(attr_id)
        if val:
            current_counts[val] = current_counts.get(val, 0) + 1

    # Define groups
    hw_group = ["Hardware", "HW", "H/W", "Hard-ware"]
    sw_group = ["Software", "SW", "S/W", "Soft"]
    control_group = "Systems"

    # Calculate expected totals based on initial state
    # We sum up all initial counts for the HW group to get the target count for "Hardware"
    expected_hw_total = sum(initial_counts.get(k, 0) for k in hw_group)
    expected_sw_total = sum(initial_counts.get(k, 0) for k in sw_group)
    expected_sys_total = initial_counts.get("Systems", 0)

    score = 0
    feedback = []

    # 1. Check Hardware Standardization (35 pts)
    final_hw_count = current_counts.get("Hardware", 0)
    # Check if any bad HW values remain
    bad_hw_remaining = sum(current_counts.get(k, 0) for k in hw_group if k != "Hardware")
    
    if bad_hw_remaining == 0 and final_hw_count == expected_hw_total:
        score += 35
        feedback.append(f"Hardware values standardized perfectly ({final_hw_count} items).")
    elif final_hw_count > 0:
        # Partial credit if some progress made
        progress = final_hw_count / expected_hw_total if expected_hw_total > 0 else 0
        pts = int(25 * progress)
        score += pts
        feedback.append(f"Partial Hardware standardization ({final_hw_count}/{expected_hw_total}).")
    else:
        feedback.append("No 'Hardware' values found.")

    # 2. Check Software Standardization (35 pts)
    final_sw_count = current_counts.get("Software", 0)
    bad_sw_remaining = sum(current_counts.get(k, 0) for k in sw_group if k != "Software")

    if bad_sw_remaining == 0 and final_sw_count == expected_sw_total:
        score += 35
        feedback.append(f"Software values standardized perfectly ({final_sw_count} items).")
    elif final_sw_count > 0:
        progress = final_sw_count / expected_sw_total if expected_sw_total > 0 else 0
        pts = int(25 * progress)
        score += pts
        feedback.append(f"Partial Software standardization ({final_sw_count}/{expected_sw_total}).")
    else:
        feedback.append("No 'Software' values found.")

    # 3. Legacy Removal (15 pts)
    # Strict check: 0 bad values allowed
    total_bad_remaining = bad_hw_remaining + bad_sw_remaining
    if total_bad_remaining == 0:
        score += 15
        feedback.append("All inconsistent values removed.")
    else:
        feedback.append(f"{total_bad_remaining} inconsistent values still remain.")

    # 4. Data Preservation (15 pts)
    # Systems count must match exactly
    final_sys_count = current_counts.get("Systems", 0)
    if final_sys_count == expected_sys_total:
        score += 15
        feedback.append("Control group (Systems) preserved correctly.")
    else:
        feedback.append(f"Control group modified! Expected {expected_sys_total}, found {final_sys_count}.")

    return {
        "passed": score >= 85,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "initial": initial_counts,
            "final": current_counts
        }
    }