#!/usr/bin/env python3
"""
Verifier for audit_inventory_archive_consistency.

VERIFICATION METRICS:
1. File Creation Anti-gaming: Report exists and was updated during task (10 pts)
2. Correct Orphan Identification: Text parses correctly to the ghost station (35 pts)
3. Correct Missing Identification: Text parses correctly to the deleted station (35 pts)
4. VLM Process Check: Trajectory frames confirm terminal usage/exploration (20 pts)
"""

import json
import os
import tempfile
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_consistency(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the exported JSON from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract state
    report_exists = result.get('report_exists', False)
    created_during_task = result.get('created_during_task', False)
    content_b64 = result.get('report_content_b64', "")
    truth_missing = result.get('truth_missing', "").lower().strip()
    truth_orphan = result.get('truth_orphan', "").lower().strip()

    score = 0
    feedback_parts = []

    # 3. Process the report file
    if not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target report file 'consistency_report.txt' was not found."
        }

    if created_during_task:
        score += 10
        feedback_parts.append("Report successfully modified during task runtime.")
    else:
        feedback_parts.append("WARNING: Report file exists but was NOT created/modified during task.")

    # Decode report content
    content = ""
    try:
        content = base64.b64decode(content_b64).decode('utf-8')
    except Exception as e:
        feedback_parts.append("Could not decode report content text.")

    # 4. Parse content using Regex (Tolerant to whitespace)
    orphan_match = re.search(r'Orphaned:\s*([A-Za-z0-9_]+)', content, re.IGNORECASE)
    missing_match = re.search(r'Missing:\s*([A-Za-z0-9_]+)', content, re.IGNORECASE)

    agent_orphan = orphan_match.group(1).lower() if orphan_match else ""
    agent_missing = missing_match.group(1).lower() if missing_match else ""

    orphan_correct = False
    missing_correct = False

    if agent_orphan == truth_orphan:
        score += 35
        orphan_correct = True
        feedback_parts.append(f"Correctly identified Orphan station: {truth_orphan.upper()}")
    else:
        feedback_parts.append(f"Orphan mismatched: Expected '{truth_orphan.upper()}', got '{agent_orphan.upper()}'")

    if agent_missing == truth_missing:
        score += 35
        missing_correct = True
        feedback_parts.append(f"Correctly identified Missing station: {truth_missing.upper()}")
    else:
        feedback_parts.append(f"Missing mismatched: Expected '{truth_missing.upper()}', got '{agent_missing.upper()}'")

    # 5. VLM Trajectory Process Verification (20 pts)
    vlm_points = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            
            vlm_prompt = """You are auditing a Linux agent's work timeline.
Look at these screenshots sampled over the task's duration. 
Did the agent use a terminal window to run commands (like 'ls', 'cd', 'mysql', 'scinv') to investigate directories or databases?

Respond EXACTLY in this JSON format:
{
    "used_terminal": true or false,
    "evidence": "brief string describing the terminal activity you see"
}"""
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_terminal"):
                    vlm_points = 20
                    feedback_parts.append("VLM verified correct terminal usage in trajectory.")
                else:
                    feedback_parts.append("VLM did not detect terminal exploration.")
            else:
                # Give grace points if VLM fails to evaluate to prevent unfair failure
                vlm_points = 20
                feedback_parts.append("VLM query failed, granting default process points.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            vlm_points = 20
            feedback_parts.append("VLM error, granting default process points.")
    else:
        vlm_points = 20
        feedback_parts.append("No VLM provided, granting default process points.")
        
    score += vlm_points

    # Determine Pass Status
    key_criteria_met = orphan_correct and missing_correct and created_during_task
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }