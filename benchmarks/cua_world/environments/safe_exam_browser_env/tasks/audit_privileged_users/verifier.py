#!/usr/bin/env python3
"""
Verifier for audit_privileged_users task.

Verification Strategy:
1. Validate that the JSON file was created during the task run (anti-gaming).
2. Read the exported ground truth users from the database.
3. Parse the agent's output JSON file.
4. Compare agent's list vs ground truth:
   - Completeness: Did they find ALL admins?
   - Accuracy: Are the usernames and roles correct?
   - False Positives: Did they include non-admins?
5. VLM verification to ensure they used the Web UI instead of just executing database queries.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_privileged_users(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/admin_audit.json')

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve the task result JSON (contains ground truth)
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check file existence and anti-gaming (file creation timestamp)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": f"Target file {expected_output_path} was not created."}
        
    if not result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File exists but was not created/modified during the task window (anti-gaming check failed)."}

    score += 10
    feedback_parts.append("File created successfully")

    # ================================================================
    # 2. Retrieve and parse the agent's JSON output
    # ================================================================
    temp_agent_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_data = None
    try:
        copy_from_env(expected_output_path, temp_agent_file.name)
        with open(temp_agent_file.name, 'r') as f:
            agent_data = json.load(f)
        score += 10
        feedback_parts.append("Valid JSON format")
    except json.JSONDecodeError:
        feedback_parts.append("File is not valid JSON")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    except Exception as e:
        feedback_parts.append(f"Failed to read agent file: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_agent_file.name):
            os.unlink(temp_agent_file.name)

    if not isinstance(agent_data, list):
        feedback_parts.append("JSON root is not a list/array")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # 3. Process Ground Truth
    # ================================================================
    db_users = result.get('db_users_ground_truth', [])
    
    # Determine the "actual" admins based on roles containing 'admin'
    ground_truth_admins = {}
    for user in db_users:
        role = user.get('role', '').lower()
        if 'admin' in role:
            ground_truth_admins[user['username'].lower()] = user

    if not ground_truth_admins:
        logger.warning("No admins found in ground truth database! This indicates a setup issue.")

    # ================================================================
    # 4. Evaluate Agent Data
    # ================================================================
    agent_usernames = set()
    valid_entries = 0
    false_positives = 0
    missing_fields = False

    for entry in agent_data:
        if not isinstance(entry, dict):
            continue
            
        # Lenient key extraction
        keys_lower = {k.lower().replace('_', ''): v for k, v in entry.items()}
        username = keys_lower.get('username')
        full_name = keys_lower.get('fullname') or keys_lower.get('name')
        role = keys_lower.get('role')

        if not username or not full_name or not role:
            missing_fields = True

        if username:
            uname_lower = str(username).lower()
            agent_usernames.add(uname_lower)
            if uname_lower not in ground_truth_admins:
                false_positives += 1
            else:
                valid_entries += 1

    # Scoring Criteria
    
    # Criterion: Did they find all the admins? (40 points)
    gt_usernames = set(ground_truth_admins.keys())
    missing_admins = gt_usernames - agent_usernames
    
    if len(gt_usernames) > 0:
        coverage_ratio = valid_entries / len(gt_usernames)
        coverage_score = int(coverage_ratio * 40)
        score += coverage_score
        
        if coverage_ratio == 1.0:
            feedback_parts.append("Found ALL privileged users")
        elif coverage_ratio > 0:
            feedback_parts.append(f"Found {valid_entries}/{len(gt_usernames)} privileged users")
        else:
            feedback_parts.append("Found ZERO privileged users")
    else:
        # Edge case: No admins existed
        score += 40

    # Criterion: No false positives (20 points)
    if false_positives == 0:
        score += 20
        feedback_parts.append("No false positives")
    else:
        penalty = min(20, false_positives * 5)
        score += (20 - penalty)
        feedback_parts.append(f"Contains {false_positives} non-admin users/false positives")

    # Criterion: No missing fields (20 points)
    if not missing_fields and len(agent_data) > 0:
        score += 20
        feedback_parts.append("All required fields present")
    elif len(agent_data) > 0:
        score += 10
        feedback_parts.append("Some objects are missing required fields (username/full_name/role)")

    # ================================================================
    # 5. VLM Trajectory Verification
    # (To prevent gaming via direct DB query script)
    # ================================================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "You are evaluating an agent's trajectory for an administrative audit task. "
            "Look at these screenshots. Did the agent navigate through a web browser (Firefox) "
            "to view a 'User Account' or 'User Management' listing page inside a web application? "
            "Reply with a JSON containing a boolean 'used_web_ui'."
        )
        
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        used_web_ui = False
        
        if vlm_resp and "parsed" in vlm_resp:
            used_web_ui = vlm_resp["parsed"].get("used_web_ui", False)
            
        if not used_web_ui:
            # If they didn't use the web UI, penalize heavily (cheating via terminal)
            logger.info("VLM indicated web UI was not used to look up users.")
            score = max(0, score - 50)
            feedback_parts.append("PENALTY: VLM analysis indicates the web interface was not used (potential direct DB query)")
        else:
            feedback_parts.append("VLM confirmed web UI navigation")
            
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # We don't fail the task if VLM is unavailable, but we log it.

    # Final pass/fail determination
    # Require 80 points (meaning JSON valid, all admins found, no/few false positives)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }