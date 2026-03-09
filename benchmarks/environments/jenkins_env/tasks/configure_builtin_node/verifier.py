#!/usr/bin/env python3
"""
Verifier for configure_builtin_node task.
Verifies Jenkins node configuration and job creation via API result.
"""

import json
import sys
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_builtin_node(traj, env_info, task_info):
    """
    Verify configure_builtin_node task.
    
    Criteria:
    1. Built-in node Executors set to 1 (15 pts)
    2. Built-in node Labels include 'controller' AND 'lightweight' (20 pts)
    3. Built-in node Usage Mode is 'EXCLUSIVE' (20 pts)
    4. Job 'controller-health-check' exists (10 pts)
    5. Job is Freestyle type (5 pts)
    6. Job is restricted to 'controller' label (15 pts)
    7. Job has shell build step (10 pts)
    8. Shell command contains expected content (5 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_builtin_node_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    max_score = 100
    details = []
    
    node = result.get("node_config", {})
    job = result.get("job", {})
    initial = result.get("initial_state", {})
    
    # --- Check Node Configuration ---
    
    # 1. Executors (15 pts)
    num_exec = node.get("num_executors", -1)
    if num_exec == 1:
        score += 15
        details.append("PASS (15/15): Executors set to 1")
    else:
        details.append(f"FAIL (0/15): Executors = {num_exec}, expected 1")
        
    # 2. Labels (20 pts)
    # Check both assigned_labels array string and label_string_top
    assigned_labels = (node.get("assigned_labels", "") or "").lower()
    label_string = (node.get("label_string_top", "") or "").lower()
    combined_labels = f"{assigned_labels} {label_string}"
    
    has_controller = "controller" in combined_labels
    has_lightweight = "lightweight" in combined_labels
    
    if has_controller and has_lightweight:
        score += 20
        details.append("PASS (20/20): Labels 'controller' and 'lightweight' found")
    elif has_controller or has_lightweight:
        score += 10
        found = "controller" if has_controller else "lightweight"
        details.append(f"PARTIAL (10/20): Found label '{found}', but missing the other")
    else:
        details.append(f"FAIL (0/20): Missing required labels. Found: '{combined_labels}'")
        
    # 3. Usage Mode (20 pts)
    # API returns 'NORMAL' (Use as much as possible) or 'EXCLUSIVE' (Only build jobs with label...)
    mode = node.get("mode", "NORMAL")
    if mode == "EXCLUSIVE":
        score += 20
        details.append("PASS (20/20): Usage mode set to EXCLUSIVE")
    else:
        details.append(f"FAIL (0/20): Usage mode is '{mode}', expected 'EXCLUSIVE' (Only build jobs with label matching this node)")

    # Anti-gaming check: ensure state changed from initial
    initial_exec = initial.get("initial_executors")
    initial_mode = initial.get("initial_mode")
    if str(num_exec) == str(initial_exec) and mode == initial_mode and not has_controller and not has_lightweight:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Anti-gaming: No changes detected from initial state.",
            "details": details
        }

    # --- Check Job Configuration ---
    
    # 4. Job Exists (10 pts)
    job_exists = job.get("exists", False)
    if job_exists:
        score += 10
        details.append("PASS (10/10): Job 'controller-health-check' exists")
    else:
        details.append("FAIL (0/10): Job 'controller-health-check' not found")
        
    if job_exists:
        # 5. Job Type (5 pts)
        job_class = job.get("class", "")
        if "FreeStyleProject" in job_class:
            score += 5
            details.append("PASS (5/5): Job is a Freestyle project")
        else:
            details.append(f"FAIL (0/5): Job type mismatch. Got: {job_class}")
            
        # 6. Label Expression (15 pts)
        label_expr = (job.get("label_expression", "") or "").strip()
        can_roam = job.get("can_roam", "true") # 'false' means restricted
        
        # Note: canRoam=false usually implies usage of assignedNode
        if "controller" in label_expr:
            score += 15
            details.append(f"PASS (15/15): Job restricted to label 'controller'")
        elif can_roam == "false" or can_roam is False:
            # Restricted but maybe wrong label?
            score += 5
            details.append(f"PARTIAL (5/15): Job is restricted, but label expression '{label_expr}' does not contain 'controller'")
        else:
            details.append(f"FAIL (0/15): Job is not restricted to 'controller' label")
            
        # 7. Shell Build Step (10 pts)
        if job.get("has_shell_step", False):
            score += 10
            details.append("PASS (10/10): Shell build step found")
        else:
            details.append("FAIL (0/10): No Execute Shell build step found")
            
        # 8. Shell Command Content (5 pts)
        cmd = (job.get("shell_command", "") or "").lower()
        if "health check" in cmd or "health_check" in cmd:
            score += 5
            details.append("PASS (5/5): Shell command content correct")
        elif job.get("has_shell_step", False):
            # Has shell but content differs
            score += 2
            details.append("PARTIAL (2/5): Shell command exists but missing expected text")
        else:
            details.append("FAIL (0/5): Shell command missing")
    else:
        details.append("SKIP (0/35): Job checks skipped (job not found)")

    passed = score >= 60
    
    feedback = f"Score: {score}/{max_score}. " + " | ".join(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }