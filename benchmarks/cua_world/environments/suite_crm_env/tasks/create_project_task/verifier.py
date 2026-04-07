#!/usr/bin/env python3
"""
Verifier for create_project_task task.
Checks database export for correct creation and field population of the Project Task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_project_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_project_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    pt_found = result.get("pt_found", False)
    initial_count = int(result.get("initial_count", 0))
    current_count = int(result.get("current_count", 0))
    
    # 1. Record Exists (20 pts)
    if pt_found:
        score += 20
        feedback_parts.append("Project Task record found (+20)")
    else:
        feedback_parts.append("Project Task record not found")
        # Anti-gaming context
        if current_count > initial_count:
            feedback_parts.append(f"Note: {current_count - initial_count} new task(s) created, but not with the expected name")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Anti-gaming: Ensure it was newly created during the task
    if current_count <= initial_count:
        feedback_parts.append("Task count did not increase (Anti-gaming check failed)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Linked to Parent Project (25 pts)
    project_name = result.get("project_name", "")
    if project_name == "HMC Server Migration Q4":
        score += 25
        feedback_parts.append("Linked to correct project (+25)")
    else:
        feedback_parts.append(f"Linked project mismatch: expected 'HMC Server Migration Q4', got '{project_name}'")

    # 3. Dates Correct (20 pts, 10 each)
    date_start = result.get("date_start", "")
    date_finish = result.get("date_finish", "")
    
    if "2025-10-15" in date_start:
        score += 10
        feedback_parts.append("Start date correct (+10)")
    else:
        feedback_parts.append(f"Start date mismatch: {date_start}")

    if "2025-10-17" in date_finish:
        score += 10
        feedback_parts.append("Finish date correct (+10)")
    else:
        feedback_parts.append(f"Finish date mismatch: {date_finish}")

    # 4. Estimated Effort (15 pts)
    effort = str(result.get("estimated_effort", ""))
    if effort in ["12", "12.0", "12.00"]:
        score += 15
        feedback_parts.append("Estimated effort correct (+15)")
    else:
        feedback_parts.append(f"Estimated effort mismatch: {effort}")

    # 5. Priority Correct (10 pts)
    priority = result.get("priority", "").lower()
    if priority == "high":
        score += 10
        feedback_parts.append("Priority correct (+10)")
    else:
        feedback_parts.append(f"Priority mismatch: {priority}")

    # 6. Description Included (10 pts)
    desc = result.get("description", "").lower()
    if "power drops" in desc and "cooling capacity" in desc and "network switch" in desc:
        score += 10
        feedback_parts.append("Description contains key phrases (+10)")
    elif "power drops" in desc or "cooling" in desc or "switch" in desc:
        score += 5
        feedback_parts.append("Description partially contains key phrases (+5)")
    else:
        feedback_parts.append("Description missing or incomplete")

    # Pass threshold is 65 points WITH record existing and correctly linked to parent
    key_criteria_met = pt_found and (project_name == "HMC Server Migration Q4")
    passed = score >= 65 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }