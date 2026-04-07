#!/usr/bin/env python3
"""
Verifier for review_activity_logs task.

Verification Strategy:
1. Verify the report file was created during the task.
2. Verify the report matches the required format.
3. Verify the counts in the report accurately match the database ground truth
   (allowing a small tolerance since the agent's own login/navigation generates logs).
4. Verify navigation evidence (VLM trajectory or increased log counts).
"""

import os
import json
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report(filepath):
    """Parse the agent's audit report."""
    try:
        with open(filepath, "r") as f:
            content = f.read()
    except Exception as e:
        return None, str(e)

    parsed = {}
    
    # Extract total
    m = re.search(r'[Tt]otal\s+(?:logged\s+)?activities\s*:\s*(\d+)', content)
    if m: parsed["total"] = int(m.group(1))
        
    # Extract CREATE count
    m = re.search(r'CREATE\s+actions?\s*:\s*(\d+)', content)
    if m: parsed["create"] = int(m.group(1))
        
    # Extract MODIFY count
    m = re.search(r'MODIFY\s+actions?\s*:\s*(\d+)', content)
    if m: parsed["modify"] = int(m.group(1))

    # Check headers/signatures
    parsed["has_super_admin"] = "super-admin" in content
    parsed["has_header"] = "Activity Audit" in content or "activity audit" in content.lower()
    
    return parsed, content


def check_vlm_for_navigation(traj, env_info):
    """Use VLM to check if the agent navigated to the User Activity Logs page."""
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return False, "No trajectory frames available"

    prompt = """
    Look at these screenshots from a web browser.
    Did the user navigate to a page showing "User Logs", "Activity Logs", or "User Activity Logs" inside the SEB Server interface?
    Look for a table or list showing actions like CREATE, MODIFY, LOGIN, etc.
    
    Respond in JSON format:
    {
        "visited_logs_page": true/false,
        "reasoning": "brief explanation"
    }
    """
    
    try:
        result = query_vlm(images=frames, prompt=prompt)
        parsed = result.get('parsed', {})
        return parsed.get('visited_logs_page', False), parsed.get('reasoning', '')
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        return False, f"VLM Error: {e}"


def verify_review_activity_logs(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Tolerances
    tolerance = task_info.get('metadata', {}).get('tolerance', 3)
    
    # 1. Retrieve exported files
    with tempfile.TemporaryDirectory() as temp_dir:
        result_path = os.path.join(temp_dir, 'task_result.json')
        gt_path = os.path.join(temp_dir, 'ground_truth.json')
        report_path = os.path.join(temp_dir, 'activity_audit.txt')
        
        try:
            copy_from_env('/tmp/task_result.json', result_path)
            with open(result_path, 'r') as f:
                result_data = json.load(f)
                
            copy_from_env('/tmp/ground_truth_activity.json', gt_path)
            with open(gt_path, 'r') as f:
                gt_data = json.load(f)
                
            file_exists = result_data.get('file_exists', False)
            if file_exists:
                copy_from_env('/tmp/activity_audit_submitted.txt', report_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification files: {e}"}

    # ================================================================
    # CRITERION 1: Report file exists and valid timestamp (10 points)
    # ================================================================
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file ~/Documents/activity_audit.txt was not found."
        }
    
    task_start = result_data.get('task_start', 0)
    file_mtime = result_data.get('file_mtime', 0)
    
    if file_mtime >= task_start:
        score += 10
        feedback_parts.append("Report file created during task")
    else:
        feedback_parts.append("Report file exists but predates task (possible gaming)")
        # Continue but no points for existence
        
    # ================================================================
    # CRITERION 2: File format correct (10 points)
    # ================================================================
    parsed_report, raw_content = parse_report(report_path)
    
    if parsed_report is None:
        return {"passed": False, "score": score, "feedback": f"Could not read report file: {raw_content}"}
        
    format_score = 0
    if parsed_report.get("has_header"): format_score += 3
    if parsed_report.get("has_super_admin"): format_score += 3
    
    fields_present = sum(1 for k in ["total", "create", "modify"] if k in parsed_report)
    if fields_present == 3:
        format_score += 4
        feedback_parts.append("Report formatting is complete")
    elif fields_present > 0:
        format_score += 2
        feedback_parts.append(f"Report formatting incomplete ({fields_present}/3 fields)")
    else:
        feedback_parts.append("Report missing required count fields")
        
    score += format_score

    # ================================================================
    # CRITERION 3-5: Value Accuracy (25 + 20 + 20 = 65 points)
    # ================================================================
    gt_total = gt_data.get('total_activities', 0)
    gt_create = gt_data.get('create_count', 0)
    gt_modify = gt_data.get('modify_count', 0)
    
    # Check total (25 pts)
    agent_total = parsed_report.get("total", -999)
    total_diff = abs(agent_total - gt_total)
    
    if agent_total == -999:
        feedback_parts.append("Missing Total count")
    elif total_diff <= tolerance:
        score += 25
        feedback_parts.append(f"Total count accurate ({agent_total} vs GT {gt_total})")
    elif total_diff <= tolerance * 3 and agent_total > gt_total:
        # Agent might have clicked around and generated extra entries
        score += 15
        feedback_parts.append(f"Total count acceptable (agent generated {total_diff} new logs)")
    else:
        feedback_parts.append(f"Total count inaccurate ({agent_total} vs GT {gt_total})")

    # Check CREATE (20 pts)
    agent_create = parsed_report.get("create", -999)
    create_diff = abs(agent_create - gt_create)
    
    if agent_create == -999:
        feedback_parts.append("Missing CREATE count")
    elif create_diff <= tolerance:
        score += 20
        feedback_parts.append(f"CREATE count accurate ({agent_create} vs GT {gt_create})")
    elif create_diff <= tolerance * 2:
        score += 10
        feedback_parts.append(f"CREATE count near GT ({agent_create} vs GT {gt_create})")
    else:
        feedback_parts.append(f"CREATE count inaccurate ({agent_create} vs GT {gt_create})")

    # Check MODIFY (20 pts)
    agent_modify = parsed_report.get("modify", -999)
    modify_diff = abs(agent_modify - gt_modify)
    
    if agent_modify == -999:
        feedback_parts.append("Missing MODIFY count")
    elif modify_diff <= tolerance:
        score += 20
        feedback_parts.append(f"MODIFY count accurate ({agent_modify} vs GT {gt_modify})")
    elif modify_diff <= tolerance * 2:
        score += 10
        feedback_parts.append(f"MODIFY count near GT ({agent_modify} vs GT {gt_modify})")
    else:
        feedback_parts.append(f"MODIFY count inaccurate ({agent_modify} vs GT {gt_modify})")

    # ================================================================
    # CRITERION 6: Navigation Evidence (15 points)
    # ================================================================
    # Did the DB log count increase? The agent logging in generates logs.
    current_total = result_data.get('current_total_activities', 0)
    
    if current_total > gt_total:
        score += 15
        feedback_parts.append("Navigation evidence found in DB")
    else:
        # Fallback to VLM
        visited, vlm_reason = check_vlm_for_navigation(traj, env_info)
        if visited:
            score += 15
            feedback_parts.append(f"Navigation confirmed via VLM: {vlm_reason}")
        else:
            feedback_parts.append(f"No navigation evidence via DB or VLM. VLM reason: {vlm_reason}")

    # ================================================================
    # FINAL DECISION
    # ================================================================
    passed = score >= 60 and fields_present > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "gt_total": gt_total,
            "gt_create": gt_create,
            "gt_modify": gt_modify,
            "agent_total": agent_total,
            "agent_create": agent_create,
            "agent_modify": agent_modify
        }
    }