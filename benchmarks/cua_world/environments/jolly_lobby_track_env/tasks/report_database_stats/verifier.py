#!/usr/bin/env python3
"""
Verifier for report_database_stats task.

Criteria:
1. Output file /home/ga/db_stats.txt must exist.
2. File must be created/modified *during* the task.
3. Content must follow the format "Visitors: X" and "Hosts: Y".
4. Values X and Y must match the ground truth (derived from CSVs) within a tolerance.
   Tolerance is used because the default DB might contain a few extra sample records.
5. VLM verification on trajectory to confirm agent actually looked at data/stats.
"""

import json
import re
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_report_stats(traj, env_info, task_info):
    """
    Verify the database statistics reporting task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Agent Result
    agent_result = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            agent_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # 2. Load Ground Truth (calculated in setup_task.sh)
    ground_truth = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ground_truth_stats.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        # Fallback if ground truth file missing
        logger.warning(f"Ground truth file missing: {e}")
        ground_truth = {"expected_visitors": 0, "expected_hosts": 0, "tolerance": 0}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # Extract Data
    file_exists = agent_result.get('file_exists', False)
    file_created = agent_result.get('file_created_during_task', False)
    content = agent_result.get('file_content', "").strip()
    
    exp_visitors = ground_truth.get('expected_visitors', 0)
    exp_hosts = ground_truth.get('expected_hosts', 0)
    tolerance = ground_truth.get('tolerance', 5)

    score = 0
    feedback_parts = []
    
    # --------------------------------------------------------------
    # SCORING CRITERIA
    # --------------------------------------------------------------

    # Criterion 1: File Existence (20 pts)
    if file_exists:
        score += 20
        feedback_parts.append("File exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file /home/ga/db_stats.txt not found"}

    # Criterion 2: Anti-Gaming (File created during task) (20 pts)
    if file_created:
        score += 20
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates it was not created during this session")

    # Criterion 3: Parse Values (20 pts for format)
    # Expected format:
    # Visitors: 123
    # Hosts: 45
    visitor_match = re.search(r'Visitors:\s*(\d+)', content, re.IGNORECASE)
    host_match = re.search(r'Hosts:\s*(\d+)', content, re.IGNORECASE)
    
    reported_visitors = None
    reported_hosts = None

    if visitor_match and host_match:
        score += 20
        feedback_parts.append("Format correct")
        reported_visitors = int(visitor_match.group(1))
        reported_hosts = int(host_match.group(1))
    else:
        feedback_parts.append("Incorrect format. Expected 'Visitors: [n]' and 'Hosts: [n]'")

    # Criterion 4: Value Accuracy (40 pts)
    # Split 20 pts for visitors, 20 pts for hosts
    accuracy_passed = False
    
    if reported_visitors is not None:
        # Visitors check
        if abs(reported_visitors - exp_visitors) <= tolerance:
            score += 20
            feedback_parts.append(f"Visitor count accurate ({reported_visitors})")
        else:
            feedback_parts.append(f"Visitor count mismatch (Reported: {reported_visitors}, Expected: {exp_visitors} +/- {tolerance})")

        # Hosts check
        if abs(reported_hosts - exp_hosts) <= tolerance:
            score += 20
            feedback_parts.append(f"Host count accurate ({reported_hosts})")
        else:
            feedback_parts.append(f"Host count mismatch (Reported: {reported_hosts}, Expected: {exp_hosts} +/- {tolerance})")
            
        if (abs(reported_visitors - exp_visitors) <= tolerance) and (abs(reported_hosts - exp_hosts) <= tolerance):
            accuracy_passed = True

    # Criterion 5: VLM Verification (Bonus/Confirmation)
    # We verify the agent actually looked at a screen with numbers
    frames = sample_trajectory_frames(traj, n=4)
    vlm_score = 0
    if frames:
        vlm_prompt = (
            "Does the user appear to be viewing a 'Database', 'Records', 'Statistics', or 'Report' screen "
            "in the Lobby Track software? "
            "Are there lists of people or counters visible (e.g., 'Record 1 of X')? "
            "Answer yes/no with reasoning."
        )
        try:
            vlm_resp = query_vlm(frames, vlm_prompt)
            if vlm_resp.get("success") and "yes" in vlm_resp.get("result", "").lower():
                # If they got the numbers wrong but VLM says they tried, we might give partial credit
                # But here we stick to strict scoring for now, just append feedback
                feedback_parts.append("VLM confirmed stats/records view")
        except Exception:
            pass

    # Final Pass Decision
    # Must have file, correct format, created during task, AND accurate numbers
    passed = (score >= 90)  # Allows small margin of error elsewhere, but basically needs perfection

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }