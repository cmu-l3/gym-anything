#!/usr/bin/env python3
"""
Verifier for create_health_check_script task.

Scoring Criteria:
1. Script Creation (20 pts): Exists, executable, looks like a script.
2. Report Generation (20 pts): Valid JSON file exists.
3. Data Accuracy (40 pts): Record counts match actual DB state.
4. System Checks (20 pts): Server status, DB size, Disk space within tolerance.
5. Anti-Gaming: Report must be generated during task time.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_health_check_script(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    script_info = result.get("script_info", {})
    report_info = result.get("report_info", {})
    agent_report = result.get("agent_report", {})
    ground_truth = result.get("ground_truth", {})
    
    # ---------------------------------------------------------
    # Criterion 1: Script Integrity (20 pts)
    # ---------------------------------------------------------
    if script_info.get("exists"):
        score += 10
        feedback.append("✓ Script file created")
        if script_info.get("executable"):
            score += 5
            feedback.append("✓ Script is executable")
        else:
            feedback.append("✗ Script is not executable")
            
        if script_info.get("content_heuristic_score", 0) >= 2:
            score += 5
            feedback.append("✓ Script contains expected commands")
    else:
        feedback.append("✗ Script file not found")

    # ---------------------------------------------------------
    # Criterion 2: Report Validity (20 pts)
    # ---------------------------------------------------------
    if report_info.get("exists"):
        if report_info.get("valid_json"):
            score += 10
            feedback.append("✓ Report is valid JSON")
            
            # Anti-gaming: Created during task?
            if report_info.get("created_during_task"):
                score += 10
                feedback.append("✓ Report generated during task")
            else:
                feedback.append("✗ Report timestamp is old (pre-existing?)")
        else:
            feedback.append("✗ Report file exists but is not valid JSON")
    else:
        feedback.append("✗ Report file not found")

    # If report isn't valid, we can't check contents
    if not report_info.get("valid_json"):
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # ---------------------------------------------------------
    # Criterion 3: Data Accuracy (40 pts)
    # ---------------------------------------------------------
    agent_records = agent_report.get("records", {})
    gt_records = ground_truth.get("records", {})
    
    # Required keys to check
    keys_to_check = ["aircraft", "operators", "persons", "flight_plans", "flight_operations", "users"]
    
    matches = 0
    for key in keys_to_check:
        agent_val = agent_records.get(key)
        gt_val = gt_records.get(key)
        
        # Mapping for potential key mismatches if agent uses slightly different names
        if agent_val is None and key == "operators": agent_val = agent_records.get("companies")
        
        if agent_val is not None and agent_val == gt_val:
            matches += 1
        else:
            feedback.append(f"✗ Count mismatch for {key}: Agent={agent_val}, Actual={gt_val}")
    
    # Proportional score
    accuracy_score = int((matches / len(keys_to_check)) * 40)
    score += accuracy_score
    feedback.append(f"✓ DB Records Accuracy: {matches}/{len(keys_to_check)} correct ({accuracy_score} pts)")

    # ---------------------------------------------------------
    # Criterion 4: System Checks (20 pts)
    # ---------------------------------------------------------
    # Server status
    server_info = agent_report.get("server", {})
    if server_info.get("admin_accessible") is True and server_info.get("admin_http_status") in [200, 302, 301]:
        score += 10
        feedback.append("✓ Server status reported correctly")
    else:
        feedback.append("✗ Server status incorrect or missing")

    # DB Size
    agent_db = agent_report.get("database", {})
    gt_db = ground_truth.get("database", {})
    
    agent_size = agent_db.get("size_bytes", 0)
    gt_size = gt_db.get("size_bytes", 0)
    
    # Allow 10% tolerance
    if gt_size > 0 and abs(agent_size - gt_size) / gt_size < 0.1:
        score += 5
        feedback.append("✓ Database file size reported correctly")
    else:
        feedback.append(f"✗ Database size mismatch: Agent={agent_size}, Actual={gt_size}")

    # Partition free space (Sanity check only, > 1GB)
    disk_info = agent_report.get("disk", {})
    free_gb = disk_info.get("partition_free_gb", 0)
    if isinstance(free_gb, (int, float)) and free_gb > 0.1:
        score += 5
        feedback.append("✓ Disk space reported plausible value")
    else:
        feedback.append("✗ Disk space missing or invalid")

    # ---------------------------------------------------------
    # Final Pass Calculation
    # ---------------------------------------------------------
    passed = (score >= 65) and report_info.get("valid_json")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }