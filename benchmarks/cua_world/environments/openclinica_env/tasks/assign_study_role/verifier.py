#!/usr/bin/env python3
"""
Verifier for assign_study_role task.

Uses a multi-criteria scoring system via exported database queries to prevent gaming:
- Output exists in DB
- Corresponds to the correct role identity
- Timestamp validates it occurred during task context
- Audit log ensures GUI interactions were used
- Vision Language Model (VLM) checks execution trajectory
"""

import json
import tempfile
import os
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def verify_assign_study_role(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely load the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/assign_study_role_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Validate file integrity with anti-tampering nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get('result_nonce', '')
    if expected_nonce and result_nonce != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch"}

    score = 0
    feedback_parts = []

    # Criterion 1: Role exists (40 pts)
    role_exists = result.get('role_exists', False)
    if role_exists:
        score += 40
        feedback_parts.append("Role successfully assigned to 'monitor_user' in CV-REG-2023 (+40)")
    else:
        feedback_parts.append("FAIL: No role assigned to 'monitor_user' in CV-REG-2023 (0/40)")

    # Criterion 2: Correct role type (30 pts)
    role_name = result.get('role_name', '').strip().lower()
    if role_exists and role_name == 'monitor':
        score += 30
        feedback_parts.append("Assigned role is precisely 'Monitor' (+30)")
    elif role_exists:
        feedback_parts.append(f"FAIL: Assigned role is '{role_name}', expected 'monitor' (0/30)")

    # Criterion 3: Role is active (15 pts)
    status_id = result.get('status_id', 0)
    if role_exists and status_id == 1:
        score += 15
        feedback_parts.append("Role status is correctly flagged as active (+15)")
    elif role_exists:
        feedback_parts.append(f"FAIL: Role status is {status_id}, expected 1 (0/15)")

    # Criterion 4: Temporal anti-gaming check (15 pts)
    date_created = result.get('date_created', 0)
    task_start = result.get('task_start_time', 0)
    if role_exists and date_created >= task_start:
        score += 15
        feedback_parts.append("Role was verified as created during task execution (+15)")
    elif role_exists:
        feedback_parts.append("FAIL: Role created before task start (possible gaming) (0/15)")

    # Anti-gaming: Audit log detection (Penalty)
    audit_count = result.get('audit_log_count', 0)
    audit_baseline = result.get('audit_baseline_count', 0)
    if role_exists and (audit_count <= audit_baseline):
        score -= 20
        feedback_parts.append("PENALTY: No valid GUI interaction detected in system audit logs (-20)")

    # VLM Verification Bonus (+5 points)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames

            if images:
                prompt = (
                    "You are verifying if a user successfully navigated an electronic data capture system's interface "
                    "to assign a role. Look at these trajectory frames and the final screenshot. "
                    "Do you see the 'Set User Role' screen, a user list, or confirmation that "
                    "'monitor_user' (Jane Monitor) was assigned the 'Monitor' role for 'Cardiovascular Outcomes Registry'?"
                    "Respond with a brief confirmation."
                )
                vlm_result = query_vlm(images=images, prompt=prompt)
                resp_text = str(vlm_result.get("response", "")).lower()
                if vlm_result and ("yes" in resp_text or "confirm" in resp_text or "success" in resp_text):
                    score += 5
                    feedback_parts.append("VLM visual verification confirmed task trajectory (+5)")
        except Exception as e:
            logger.warning(f"VLM verification failed to process: {e}")

    # Enforce min/max boundaries
    score = min(max(score, 0), 100)
    
    # Check absolute pass thresholds (score >= 70, must exist & match role type)
    key_criteria_met = role_exists and (role_name == 'monitor')
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }